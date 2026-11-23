@Tags(['pg'])
library;

import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/root_router.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/entity/invite_acceptance.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

const _inviter = 'Ufaced0000001';
const _friend = 'Ufaced0000002';
const _otherInvitee = 'Ufaced0000003';
const _origin = 'http://127.0.0.1:2080';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PLAIN_INVITE_MUTUAL_FRIENDS_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_plain_invite_friends',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  late Connection writer;
  late InvitationCase invitations;

  setUpAll(() async {
    final session = await setUpDisposablePgWriter(target: target);
    addTearDown(() async {
      try {
        await getIt.reset();
      } finally {
        await tearDownDisposablePgWriter(session: session);
      }
    });
    writer = session.writer;
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
    invitations = getIt<InvitationCase>();
  });

  setUp(() async {
    await writer.execute('''
TRUNCATE public.attention_occurrence, public.invitation, public."user" CASCADE
''');
    const people = {
      _inviter: 'Alice',
      _friend: 'Bob',
      _otherInvitee: 'Charlie',
    };
    for (final (index, person) in people.entries.indexed) {
      await writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @name, @key)
'''),
        parameters: {
          'id': person.key,
          'name': person.value,
          'key': pgTestPublicKey('plaininvitefriends', index + 1),
        },
      );
    }
    await writer.execute(
      Sql.named('''
INSERT INTO public.vote_user (subject, object, amount)
VALUES (@inviter, @friend, 1), (@friend, @inviter, 1)
'''),
      parameters: {'inviter': _inviter, 'friend': _friend},
    );
  });

  Future<({String? beaconId, String? invitedId, DateTime? acceptedAt})>
  readInvite(String code) async {
    final rows = await writer.execute(
      Sql.named('''
SELECT beacon_id, invited_id, accepted_at
FROM public.invitation
WHERE id = @code
'''),
      parameters: {'code': code},
    );
    final row = rows.single;
    return (
      beaconId: row[0] as String?,
      invitedId: row[1] as String?,
      acceptedAt: row[2] as DateTime?,
    );
  }

  Future<String> issuePlainInvite() async {
    final invite = await invitations.create(
      userId: _inviter,
      addresseeName: 'Guest',
    );
    expect(await readInvite(invite.id), (
      beaconId: null,
      invitedId: null,
      acceptedAt: null,
    ));
    return invite.id;
  }

  Future<InviteAcceptance> acceptAsFriend(String code) =>
      invitations.acceptAsExisting(code: code, userId: _friend);

  group('Plain invites between mutual friends', () {
    test('accepting records the friend and the acceptance time', () async {
      final code = await issuePlainInvite();

      expect(await acceptAsFriend(code), InviteAcceptance.accepted);

      final accepted = await readInvite(code);
      expect(accepted.invitedId, _friend);
      expect(accepted.acceptedAt, isNotNull);
    });

    test(
      'reusing an accepted code is refused and preserves the claim',
      () async {
        final code = await issuePlainInvite();
        expect(await acceptAsFriend(code), InviteAcceptance.accepted);
        final firstClaim = await readInvite(code);

        await expectLater(
          acceptAsFriend(code),
          throwsA(isA<IdNotFoundException>()),
        );

        expect(await readInvite(code), firstClaim);
        expect(firstClaim.invitedId, _friend);
        expect(firstClaim.acceptedAt, isNotNull);
      },
    );

    test(
      'a code already used by someone else keeps its original claim',
      () async {
        final code = await issuePlainInvite();
        expect(
          await invitations.acceptAsExisting(code: code, userId: _otherInvitee),
          InviteAcceptance.accepted,
        );
        final firstClaim = await readInvite(code);
        expect(firstClaim.invitedId, _otherInvitee);
        expect(firstClaim.acceptedAt, isNotNull);

        await expectLater(
          acceptAsFriend(code),
          throwsA(isA<IdNotFoundException>()),
        );

        expect(await readInvite(code), firstClaim);
      },
    );

    test('an expired code is refused and stays unclaimed', () async {
      final code = await issuePlainInvite();
      await writer.execute(
        Sql.named('''
UPDATE public.invitation SET created_at = @createdAt WHERE id = @code
'''),
        parameters: {
          'code': code,
          'createdAt': DateTime.now().toUtc().subtract(
            kInvitationTTL + const Duration(days: 1),
          ),
        },
      );
      final expired = await readInvite(code);

      await expectLater(
        acceptAsFriend(code),
        throwsA(isA<IdNotFoundException>()),
      );

      expect(await readInvite(code), expired);
      expect(expired.invitedId, isNull);
      expect(expired.acceptedAt, isNull);
    });

    test('the authenticated endpoint accepts the code once', () async {
      final code = await issuePlainInvite();
      final api = (await getIt.getAsync<RootRouter>()).routeHandler();
      final token = getIt<AuthCase>().issueAccessToken(_friend).rawToken;

      Future<Response> postAccept() async => api(
        Request(
          'POST',
          Uri.parse('$_origin/api/v2/invite/$code/accept-as-existing'),
          headers: {'authorization': 'Bearer $token'},
        ),
      );

      final first = await postAccept();
      final firstBody = await first.readAsString();
      expect(first.statusCode, 200, reason: firstBody);
      expect(jsonDecode(firstBody), {'ok': true, 'requestLapsed': false});

      final repeat = await postAccept();
      expect(repeat.statusCode, 404, reason: await repeat.readAsString());
    });
  });
}
