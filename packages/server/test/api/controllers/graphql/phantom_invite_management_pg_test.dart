@Tags(['pg', 'multi-connection'])
library;

import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:shelf_plus/shelf_plus.dart' show Handler, Request;
import 'package:test/test.dart';

import 'package:tentura_server/api/root_router.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/pg_test_public_keys.dart';
import '../../../support/session_database_di_harness.dart';

const _owner = 'U1a117e000011';
const _joiner = 'U1a117e000012';
const _person = 'PH000000000011';
const _name = 'Anna K.';
const _newName = 'Anna Karenina';
const _origin = 'http://127.0.0.1:2080';
const _ensure = 'phantomInviteEnsure';
const _rotate = 'phantomInviteRotate';
const _delete = 'phantomDelete';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PHANTOM_INVITE_MANAGEMENT_TEST_DB',
    defaultNamePrefix: 'tentura_test_phantom_invite_mgmt',
  );
  final skip = await pgSkipReason(target);

  group('V2 invites for people not on Tentura yet', () {
    late _Fixtures fixtures;
    late _InviteApi api;

    setUpAll(() async {
      final previousWarning =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(() {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning;
      });
      final session = await setUpDisposablePgWriter(target: target);
      addTearDown(() => tearDownDisposablePgWriter(session: session));
      addTearDown(() async {
        getIt.skipDoubleRegistration = false;
        await getIt.reset();
      });
      fixtures = _Fixtures(session.writer);

      final db = target.databaseEnv;
      await configureSessionDatabaseTestGraph(
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
          maxConnectionCount: 8,
          workersCount: 1,
          printEnv: false,
          isDebugModeOn: false,
        ),
      );
      api = _InviteApi((await getIt.getAsync<RootRouter>()).routeHandler());
      await api.readInviteResultKinds();
    });

    setUp(() => fixtures.reset());

    group('copying an invite link', () {
      test('creates one invite for the owner with the person’s name', () async {
        expect(await fixtures.invitations(), isEmpty);

        final id = _invitationId(await api.personMutation(_ensure), _ensure);

        expect(await fixtures.invitations(), [_pendingInvite(id)]);
      });

      test('two successive copies return the same code', () async {
        final first = await api.personMutation(_ensure);
        final second = await api.personMutation(_ensure);

        final id = _invitationId(first, _ensure);
        expect(_invitationId(second, _ensure), id);
        expect(await fixtures.invitations(), [_pendingInvite(id)]);
      });

      test('two simultaneous copies return the same code', () async {
        final replies = await Future.wait([
          api.personMutation(_ensure),
          api.personMutation(_ensure),
        ]).timeout(const Duration(seconds: 30));

        final id = _invitationId(replies.first, _ensure);
        expect(_invitationId(replies.last, _ensure), id);
        expect(await fixtures.invitations(), [_pendingInvite(id)]);
      });

      test('a code issued eight days ago is still the code to share', () async {
        final existing = await fixtures.seedInvite(ageInDays: 8);
        final before = await fixtures.invitations();

        final id = _invitationId(await api.personMutation(_ensure), _ensure);

        expect(id, existing);
        expect(await fixtures.invitations(), before);
      });
    });

    group('requesting a new link', () {
      test('the replacement code works and the old code is invalid', () async {
        const currentName = 'Anna on the map';
        final oldId = await fixtures.seedInvite();
        // A pre-existing invite may have a stale recipient name.
        await fixtures.setPersonName(currentName);
        expect(await api.previewStatus(oldId), 'available');

        final newId = _invitationId(await api.personMutation(_rotate), _rotate);

        expect(newId, isNot(oldId));
        expect(await fixtures.invitations(), [
          _pendingInvite(newId, name: currentName),
        ]);
        expect(await api.previewStatus(oldId), 'invalid');
        expect(await api.previewStatus(newId), 'available');
      });

      test(
        'a person already linked to an account keeps their invite history',
        () async {
          await fixtures.seedInvite(claimed: true);
          await fixtures.markMerged();
          final before = await fixtures.invitations();

          final reply = await api.personMutation(_rotate);

          expect(await fixtures.invitations(), before);
          _expectRefusal(reply, _rotate);
        },
      );

      test(
        'a person with no current invite does not get a replacement',
        () async {
          final reply = await api.personMutation(_rotate);

          expect(await fixtures.invitations(), isEmpty);
          _expectRefusal(reply, _rotate);
        },
      );
    });

    group('an invitation on another owner’s map', () {
      for (final (mutation, action) in [
        (_ensure, 'copying a link'),
        (_rotate, 'replacing a link'),
      ]) {
        test('$action as another account returns not-found', () async {
          if (mutation == _rotate) await fixtures.seedInvite();
          final before = await fixtures.invitations();
          final missing = await api.rename(_newName, actor: _joiner);
          const notFound = '1002';
          expect(missing['errors'], [
            containsPair('extensions', containsPair('code', notFound)),
          ], reason: jsonEncode(missing));

          final reply = await api.personMutation(mutation, actor: _joiner);

          expect(await fixtures.invitations(), before);
          _expectRefusal(reply, mutation, code: notFound);
        });
      }
    });

    group('a person whose invite was claimed and account link is queued', () {
      setUp(() async {
        final id = await fixtures.seedInvite(claimed: true);
        await fixtures.queueLink(id);
      });

      for (final (mutation, action) in [
        (_ensure, 'copying their link'),
        (_rotate, 'replacing their link'),
      ]) {
        test(
          '$action reports that they are joining and leaves records intact',
          () async {
            final person = await fixtures.person();
            final invites = await fixtures.invitations();
            final jobs = await fixtures.jobs();

            final reply = await api.personMutation(mutation);

            _expectJoining(reply, mutation);
            expect(await fixtures.person(), person);
            expect(await fixtures.invitations(), invites);
            expect(await fixtures.jobs(), jobs);
          },
        );
      }

      test(
        'renaming updates the claimed invite while removal is refused',
        () async {
          final invites = await fixtures.invitations();
          final jobs = await fixtures.jobs();

          expect(await api.rename(_newName), _renamed);

          expect(
            await fixtures.person(),
            containsPair('display_name', _newName),
          );
          expect(
            (await fixtures.invitations()).single,
            allOf(
              containsPair('id', invites.single['id']),
              containsPair('invited_id', _joiner),
              containsPair('addressee_name', _newName),
            ),
          );
          expect(await fixtures.jobs(), jobs);

          final renamedPerson = await fixtures.person();
          final renamedInvites = await fixtures.invitations();
          final reply = await api.personMutation(_delete);

          _expectJoining(reply, _delete);
          expect(await fixtures.person(), renamedPerson);
          expect(await fixtures.invitations(), renamedInvites);
          expect(await fixtures.jobs(), jobs);
        },
      );
    });

    group('editing recipient names', () {
      test(
        'a shared recipient name follows map edits and refuses direct edits',
        () async {
          const firstName = 'Anna on the map';
          expect(await api.rename(firstName), _renamed);
          expect(
            await fixtures.person(),
            containsPair('display_name', firstName),
          );
          expect(await fixtures.invitations(), isEmpty);
          final id = await fixtures.seedInvite(name: firstName);
          final original = await fixtures.person();
          const rejectedName = 'Rejected Name';
          await fixtures.rejectInviteName(rejectedName);
          addTearDown(fixtures.allowInviteNames);

          final failedRename = await api.rename(rejectedName);
          expect(
            failedRename['errors'],
            isNotEmpty,
            reason: jsonEncode(failedRename),
          );
          expect(await fixtures.person(), original);
          expect(await fixtures.invitations(), [
            _pendingInvite(id, name: firstName),
          ]);

          expect(await api.rename(_newName), _renamed);

          expect(
            await fixtures.person(),
            containsPair('display_name', _newName),
          );
          expect(await fixtures.invitations(), [
            _pendingInvite(id, name: _newName),
          ]);
          final reply = await api.updateInvitation(id, firstName);

          _expectRefusal(reply, 'invitationUpdate');
          expect(await fixtures.invitations(), [
            _pendingInvite(id, name: _newName),
          ]);
        },
      );

      test(
        'direct edits work for ordinary invitations and leave linked names intact',
        () async {
          final ordinary = await fixtures.seedInvite(person: null);
          final linked = await fixtures.seedInvite();

          expect(await api.updateInvitation(ordinary, _newName), {
            'data': {
              'invitationUpdate': {'id': ordinary, 'addressee_name': _newName},
            },
          });
          expect(
            await fixtures.invitations(),
            unorderedEquals([
              _pendingInvite(ordinary, name: _newName, person: null),
              _pendingInvite(linked),
            ]),
          );

          final reply = await api.updateInvitation(linked, _newName);

          _expectRefusal(reply, 'invitationUpdate');
          expect(
            await fixtures.invitations(),
            unorderedEquals([
              _pendingInvite(ordinary, name: _newName, person: null),
              _pendingInvite(linked),
            ]),
          );
        },
      );
    });
  }, skip: skip);
}

const _renamed = {
  'data': {'phantomUpdate': true},
};

Matcher _pendingInvite(
  String id, {
  String name = _name,
  String? person = _person,
}) => allOf(
  containsPair('id', id),
  containsPair('user_id', _owner),
  containsPair('phantom_id', person),
  containsPair('addressee_name', name),
  containsPair('invited_id', null),
);

Object? _data(Map<String, Object?> reply, String field) =>
    (reply['data'] as Map<String, dynamic>?)?[field];

String _invitationId(Map<String, Object?> reply, String field) {
  expect(reply['errors'], isNull, reason: jsonEncode(reply));
  final result = _data(reply, field);
  final id = result is Map<String, dynamic> ? result['id'] : result;
  expect(id, allOf(isA<String>(), isNotEmpty), reason: jsonEncode(reply));
  return id! as String;
}

void _expectRefusal(Map<String, Object?> reply, String field, {String? code}) {
  // A GraphQL validation failure or an internal failure is not a refusal.
  expect(reply['errors'], [
    containsPair(
      'extensions',
      containsPair('code', code ?? allOf(isNotNull, isNot('1000'))),
    ),
  ], reason: jsonEncode(reply));
  expect(_data(reply, field), isNull, reason: jsonEncode(reply));
}

void _expectJoining(Map<String, Object?> reply, String field) {
  _expectRefusal(reply, field);
  expect(
    jsonEncode(reply['errors']),
    matches(RegExp('joining[ _-]*right[ _-]*now', caseSensitive: false)),
  );
}

final class _InviteApi {
  _InviteApi(this._handler);

  final Handler _handler;
  final _objectResults = <String>{};

  Future<void> readInviteResultKinds() async {
    final reply = await _graphql('''
      { __type(name: "Mutation") { fields { name type { kind ofType { kind } } } } }
    ''', const {});
    expect(reply['errors'], isNull, reason: jsonEncode(reply));
    final type = _data(reply, '__type')! as Map<String, dynamic>;
    final fields = (type['fields']! as List<dynamic>)
        .cast<Map<String, dynamic>>();
    for (final field in fields) {
      final name = field['name']! as String;
      final result = field['type'] as Map<String, dynamic>;
      final kind = result['kind'] == 'NON_NULL'
          ? (result['ofType'] as Map<String, dynamic>)['kind']
          : result['kind'];
      if (kind == 'OBJECT') _objectResults.add(name);
    }
  }

  Future<Map<String, Object?>> personMutation(
    String field, {
    String actor = _owner,
  }) => _graphql(
    r'mutation ManageLink($id: String!) { '
    '$field(id: \$id)${_objectResults.contains(field) ? ' { id }' : ''} }',
    {'id': _person},
    actor: actor,
  );

  Future<Map<String, Object?>> rename(String name, {String actor = _owner}) =>
      _graphql(
        r'mutation Rename($id: String!, $name: String!) {'
        r' phantomUpdate(id: $id, name: $name) }',
        {'id': _person, 'name': name},
        actor: actor,
      );

  Future<Map<String, Object?>> updateInvitation(
    String id,
    String name,
  ) => _graphql(
    r'mutation RenameInvite($id: String!, $name: String!) {'
    r' invitationUpdate(id: $id, addresseeName: $name) { id addressee_name } }',
    {'id': id, 'name': name},
  );

  Future<Object?> previewStatus(String id) async {
    final response = await _handler(
      Request('GET', Uri.parse('$_origin/api/v2/invite/$id/preview')),
    );
    final body = await response.readAsString();
    expect(response.statusCode, 200, reason: body);
    return (jsonDecode(body) as Map<String, Object?>)['codeStatus'];
  }

  Future<Map<String, Object?>> _graphql(
    String query,
    Map<String, Object?> variables, {
    String actor = _owner,
  }) async {
    final token = getIt<AuthCase>().issueAccessToken(actor).rawToken;
    final response = await _handler(
      Request(
        'POST',
        Uri.parse('$_origin/api/v2/graphql'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $token',
        },
        body: jsonEncode({'query': query, 'variables': variables}),
      ),
    );
    final body = await response.readAsString();
    expect(response.statusCode, 200, reason: body);
    return jsonDecode(body) as Map<String, Object?>;
  }
}

final class _Fixtures {
  const _Fixtures(this._writer);

  final Connection _writer;

  Future<void> reset() async {
    await _writer.execute('TRUNCATE TABLE public."user" CASCADE');
    for (final (index, id) in [_owner, _joiner].indexed) {
      await _writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
        parameters: {'id': id, 'key': pgTestPublicKey('personlink', index + 1)},
      );
    }
    await _writer.executeWithOwnerScopes(
      [_owner],
      Sql.named('''
INSERT INTO public.phantom (id, owner_id, display_name)
VALUES (@id, @owner, @name)
'''),
      parameters: {'id': _person, 'owner': _owner, 'name': _name},
    );
  }

  Future<String> seedInvite({
    String? person = _person,
    String name = _name,
    int ageInDays = 0,
    bool claimed = false,
  }) async {
    final result = await _writer.executeWithOwnerScopes(
      [_owner],
      Sql.named('''
INSERT INTO public.invitation
  (user_id, phantom_id, addressee_name, created_at, invited_id, accepted_at, invite_origin)
VALUES (@owner, @person, @name, now() - @days::int * interval '1 day',
        @claimant::text,
        CASE WHEN @claimant IS NOT NULL THEN now() END,
        CASE WHEN @claimant IS NOT NULL THEN 'existing_account' END)
RETURNING id
'''),
      parameters: {
        'owner': _owner,
        'person': person,
        'name': name,
        'days': ageInDays,
        'claimant': claimed ? _joiner : null,
      },
    );
    return result.single.single! as String;
  }

  Future<void> setPersonName(String name) async {
    await _writer.executeWithOwnerScopes(
      [_owner],
      Sql.named('''
UPDATE public.phantom SET display_name = @name WHERE id = @id
'''),
      parameters: {'id': _person, 'name': name},
    );
  }

  Future<void> markMerged() async {
    await _writer.executeWithOwnerScopes(
      [_owner],
      Sql.named('''
UPDATE public.phantom
SET merged_at = now(), merged_user_id = @joiner, merge_origin = 2
WHERE id = @id
'''),
      parameters: {'id': _person, 'joiner': _joiner},
    );
  }

  Future<void> queueLink(String id) async {
    await _writer.execute(
      Sql.named('''
INSERT INTO public.phantom_merge_job
  (id, phantom_id, owner_id, user_id, origin, invitation_id, state)
VALUES ('PM000000000011', @person, @owner, @joiner, 2, @id, 'queued')
'''),
      parameters: {
        'person': _person,
        'owner': _owner,
        'joiner': _joiner,
        'id': id,
      },
    );
  }

  Future<void> rejectInviteName(String name) async {
    // This name is legal through V2. Fail only the mirror write at the DB.
    await _writer.execute('''
ALTER TABLE public.invitation ADD CONSTRAINT test_reject_recipient_name
CHECK (addressee_name <> '$name')
''');
  }

  Future<void> allowInviteNames() async {
    await _writer.execute('''
ALTER TABLE public.invitation DROP CONSTRAINT test_reject_recipient_name
''');
  }

  Future<Map<String, Object?>?> person() async {
    final rows = await _writer.execute(
      Sql.named('SELECT * FROM public.phantom WHERE id = @id'),
      parameters: {'id': _person},
    );
    return rows.singleOrNull?.toColumnMap();
  }

  Future<List<Map<String, Object?>>> invitations() async => [
    for (final row in await _writer.execute(
      'SELECT * FROM public.invitation ORDER BY id',
    ))
      row.toColumnMap(),
  ];

  Future<List<Map<String, Object?>>> jobs() async => [
    for (final row in await _writer.execute(
      'SELECT * FROM public.phantom_merge_job ORDER BY id',
    ))
      row.toColumnMap(),
  ];
}
