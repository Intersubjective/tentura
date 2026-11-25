@Tags(['pg'])
library;

import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:shelf_plus/shelf_plus.dart' show Handler, Request, Response;
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart'
    show kGlobalInputQueryJwt;
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_invitation.dart';
import 'package:tentura_server/api/root_router.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/entity/invitation_entity.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/invitation_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

const _issuer = 'U1a117e000001';
const _holder = 'U1a117e000002';
const _person = 'PH000000000001';
const _privateName = 'Private Name';
const _origin = 'http://127.0.0.1:2080';
const _newAccountName = 'New Account';

final _expiredInvitation = isA<InvitationWrongException>().having(
  (error) => error.reason,
  'reason',
  InvitationWrongReason.expired,
);

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PERSON_LINKED_INVITATION_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_person_invite',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  late Connection writer;
  late Handler api;
  late UserRepositoryPort users;
  late InvitationRepositoryPort invitations;

  setUpAll(() async {
    final previousWarning = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    addTearDown(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning;
    });
    final session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
    addTearDown(() async {
      try {
        await getIt.reset();
      } finally {
        await tearDownDisposablePgWriter(session: session);
      }
    });
    final db = target.databaseEnv;
    await configureDependencies(
      Env(
        environment: Environment.dev,
        serverUri: Uri.parse(_origin),
        publicOrigin: _origin,
        publicKey: Env.kJwtPublicKey,
        privateKey: Env.kJwtPrivateKey,
        pgHost: db.pgHost,
        pgPort: db.pgPort,
        pgDatabase: db.pgDatabase,
        pgUsername: db.pgUsername,
        pgPassword: db.pgPassword,
        workersCount: 1,
        printEnv: false,
        isDebugModeOn: false,
        isNeedInvite: true,
        genealogyNodeKeySecret: 'test-genealogy-secret',
      ),
    );
    await getIt.allReady(ignorePendingAsyncCreation: true);
    api = (await getIt.getAsync<RootRouter>()).routeHandler();
    users = getIt<UserRepositoryPort>();
    invitations = getIt<InvitationRepositoryPort>();
  });

  Future<Result> query(String sql, Map<String, Object?> parameters) =>
      writer.execute(Sql.named(sql), parameters: parameters);

  setUp(() async {
    await writer.execute('''
TRUNCATE public.attention_occurrence, public.invitation, public."user" CASCADE
''');
    for (final (index, id) in [_issuer, _holder].indexed) {
      await query(
        '''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @name, @key)
''',
        {
          'id': id,
          'name': index == 0 ? 'Invite Issuer' : 'Code Holder',
          'key': pgTestPublicKey('personinvite', index + 1),
        },
      );
    }
    await writer.executeWithOwnerScopes(
      [_issuer],
      Sql.named('''
INSERT INTO public.phantom (id, owner_id, display_name)
VALUES (@id, @owner, @name)
'''),
      parameters: {'id': _person, 'owner': _issuer, 'name': _privateName},
    );
  });

  Future<String> issueInvite({String? personId, int ageInDays = 0}) async {
    final rows = await query(
      '''
INSERT INTO public.invitation (user_id, phantom_id, addressee_name, created_at)
VALUES (@issuer, @person, @name, now() - @days::int * interval '1 day')
RETURNING id
''',
      {
        'issuer': _issuer,
        'person': personId,
        'name': _privateName,
        'days': ageInDays,
      },
    );
    return rows.single.single! as String;
  }

  Future<({String ordinary, String linked})> oldInvites() async => (
    ordinary: await issueInvite(ageInDays: 8),
    linked: await issueInvite(personId: _person, ageInDays: 8),
  );

  Future<Result> claims(String id) => query(
    'SELECT invited_id FROM public.invitation WHERE id = @id',
    {'id': id},
  );

  Future<String?> claimant(String id) async =>
      (await claims(id)).single.single as String?;

  Future<Response> request(
    String method,
    String path, {
    String? actor,
    String? body,
  }) async => api(
    Request(
      method,
      Uri.parse('$_origin$path'),
      headers: {
        if (body != null) 'content-type': 'application/json',
        if (actor != null)
          'authorization':
              'Bearer ${getIt<AuthCase>().issueAccessToken(actor).rawToken}',
      },
      body: body,
    ),
  );

  Future<Map<String, Object?>> graphql(
    String operation,
    String id, {
    String actor = _holder,
  }) async {
    final response = await request(
      'POST',
      '/api/v2/graphql',
      actor: actor,
      body: jsonEncode({
        'query': operation,
        'variables': {'id': id},
      }),
    );
    final body = await response.readAsString();
    expect(response.statusCode, 200, reason: body);
    return jsonDecode(body) as Map<String, Object?>;
  }

  Future<Map<String, Object?>> getInvitation(
    String id, {
    String actor = _holder,
    bool includePersonId = false,
  }) => graphql(
    r'query ReadInvitation($id: String!) { invitationById(id: $id) { '
    'id issuer { id } addressee_name ${includePersonId ? 'phantom_id' : ''}'
    ' } }',
    id,
    actor: actor,
  );

  Map<String, Object?> inviteData(
    String id, {
    String? addressee,
    bool includesPersonId = false,
    String? personId,
  }) => {
    'data': {
      'invitationById': {
        'id': id,
        'issuer': {'id': _issuer},
        'addressee_name': addressee,
        if (includesPersonId) 'phantom_id': personId,
      },
    },
  };

  const acceptById = r'''
mutation AcceptInvitation($id: String!) {
  invitationAccept(id: $id)
}
''';

  test(
    'an invitation retains its person link until the person is deleted',
    () async {
      await expectLater(
        issueInvite(personId: 'PH000000000002'),
        throwsA(
          isA<ServerException>().having(
            (error) => error.code,
            'SQLSTATE',
            '23503',
          ),
        ),
      );

      final consumed = await issueInvite(personId: _person);
      final ordinary = await issueInvite();
      await query(
        '''
UPDATE public.invitation
SET invited_id = @holder, accepted_at = now(), invite_origin = 'existing_account'
WHERE id = @id
''',
        {'id': consumed, 'holder': _holder},
      );
      expect(await claimant(consumed), _holder);

      final pending = await issueInvite(personId: _person);
      expect(await claimant(pending), isNull);
      await expectLater(
        issueInvite(personId: _person),
        throwsA(
          isA<ServerException>().having(
            (error) => error.code,
            'SQLSTATE',
            '23505',
          ),
        ),
      );

      final fromStorage = <InvitationEntity>[];
      for (final id in [consumed, pending, ordinary]) {
        final invitation = await invitations.getById(invitationId: id);
        expect(invitation?.id, id);
        fromStorage.add(invitation!);
      }

      final deleted = await writer.executeWithOwnerScopes(
        [_issuer],
        Sql.named('DELETE FROM public.phantom WHERE id = @id RETURNING id'),
        parameters: {'id': _person},
      );
      expect(deleted.single.single, _person);
      expect(await claims(consumed), isEmpty);
      expect(await claims(pending), isEmpty);
      expect(await claims(ordinary), hasLength(1));

      final personIds = fromStorage.map((invitation) => invitation.phantomId);
      expect(personIds, [_person, _person, null]);
    },
  );

  group('Invitations after eight days', () {
    test(
      'anonymous preview offers signup only for the person-linked code',
      () async {
        final ids = await oldInvites();

        Future<Object?> codeStatus(String id) async {
          final response = await request('GET', '/api/v2/invite/$id/preview');
          final body = await response.readAsString();
          expect(response.statusCode, 200, reason: body);
          final preview = jsonDecode(body) as Map<String, Object?>;
          expect(preview['callerStatus'], 'anonymous');
          return preview['codeStatus'];
        }

        expect(await codeStatus(ids.ordinary), 'expired');
        expect(await codeStatus(ids.linked), 'available');
      },
    );

    test('lookup finds only the person-linked invitation', () async {
      final ids = await oldInvites();

      expect(await getInvitation(ids.ordinary), {
        'errors': [IdNotFoundException(id: ids.ordinary).toMap],
      });
      expect(await getInvitation(ids.linked), inviteData(ids.linked));
    });

    final signupMethods = <String, Future<UserEntity> Function(String)>{
      'device key signup': (id) => users.createInvited(
        invitationId: id,
        publicKey: pgTestPublicKey('personinvite', 3),
        displayName: _newAccountName,
      ),
      'email credential signup': (id) => users.createInvitedWithCredential(
        invitationId: id,
        type: CredentialType.emailOtp,
        identifier: 'person-invite-new-account@example.test',
        displayName: _newAccountName,
      ),
    };

    for (final method in signupMethods.entries) {
      test(
        '${method.key} creates an account only with the person-linked code',
        () async {
          final ids = await oldInvites();

          await expectLater(
            method.value(ids.ordinary),
            throwsA(_expiredInvitation),
          );
          expect(await claimant(ids.ordinary), isNull);

          final account = await method.value(ids.linked);
          expect(account.id, isNot(isIn([_issuer, _holder])));
          expect(await claimant(ids.linked), account.id);
          final created = await query(
            'SELECT display_name FROM public."user" WHERE id = @id',
            {'id': account.id},
          );
          expect(created.single.single, _newAccountName);
        },
      );
    }

    test(
      'accepting by code claims only the person-linked invitation',
      () async {
        final ids = await oldInvites();

        Future<Response> accept(String id) => request(
          'POST',
          '/api/v2/invite/$id/accept-as-existing',
          actor: _holder,
        );

        final ordinary = await accept(ids.ordinary);
        expect(ordinary.statusCode, 404);
        expect(
          jsonDecode(await ordinary.readAsString()),
          IdNotFoundException(id: ids.ordinary).toMap,
        );
        expect(await claimant(ids.ordinary), isNull);

        final linked = await accept(ids.linked);
        final body = await linked.readAsString();
        expect(linked.statusCode, 200, reason: body);
        expect(jsonDecode(body), {'ok': true, 'requestLapsed': false});
        expect(await claimant(ids.linked), _holder);
      },
    );

    test(
      'accepting an ordinary invitation by id reports that it expired',
      () async {
        final id = await issueInvite(ageInDays: 8);

        // The resolver preserves the typed reason before GraphQL serializes it.
        await expectLater(
          MutationInvitation().accept.resolve!(null, {
            'id': id,
            kGlobalInputQueryJwt: const JwtEntity(sub: _holder),
          }),
          throwsA(_expiredInvitation),
        );
        expect(await claimant(id), isNull);
      },
    );

    test('accepting by id claims the person-linked invitation', () async {
      final id = await issueInvite(personId: _person, ageInDays: 8);

      expect(await graphql(acceptById, id), {
        'data': {'invitationAccept': true},
      });
      expect(await claimant(id), _holder);
    });
  });

  group('Invitation lookup privacy', () {
    test(
      'the issuer sees the stored recipient name and linked person id',
      () async {
        final id = await issueInvite(personId: _person);

        expect(
          await getInvitation(id, actor: _issuer, includePersonId: true),
          inviteData(
            id,
            addressee: _privateName,
            includesPersonId: true,
            personId: _person,
          ),
        );
      },
    );

    test(
      'another account with the code sees the invitation and issuer only',
      () async {
        final ordinary = await issueInvite();
        final linked = await issueInvite(personId: _person);

        // Check the existing name field independently of the new id field.
        expect(
          [await getInvitation(ordinary), await getInvitation(linked)],
          [inviteData(ordinary), inviteData(linked)],
        );
        expect(
          [
            await getInvitation(ordinary, includePersonId: true),
            await getInvitation(linked, includePersonId: true),
          ],
          [
            inviteData(ordinary, includesPersonId: true),
            inviteData(linked, includesPersonId: true),
          ],
        );
      },
    );
  });
}
