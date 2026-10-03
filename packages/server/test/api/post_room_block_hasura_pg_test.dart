@Tags(['pg'])
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/domain/port/invitation_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/env.dart';

import '../support/disposable_pg_target.dart';
import '../support/hasura_pg_jwt_keys.dart';
import '../support/isolated_hasura_session.dart';

/// Through a real Hasura, role `user` stops reading the room participants of a
/// Post once the author and the viewer are blocked in either direction, while
/// the participants of a Request stay readable. The Post member reached the
/// room through the forwarder, so the block does not remove their row.
///
/// After the block the member gets no participant rows of the Post. Their own
/// row may remain only because the separate `user_id = me` branch is
/// unchanged, so an empty result and a result holding just that row are both
/// accepted; any row of another participant is not.
/// See `docs/plans/post-and-constellation-composer-plan.md` §4.7.
const _author = 'Uhroomgateauth1';
const _forwarder = 'Uhroomgatefwd01';
const _recipient = 'Uhroomgaterec01';

const _post = 'Bhroomgatepost01';
const _request = 'Bhroomgatereq001';

/// No participant row other than the viewer's own.
final _noRowsBeyondOwn = anyOf(isEmpty, equals({_recipient}));

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_ROOM_BLOCK_HASURA_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_room_hasura',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }
  final dockerReachable = await IsolatedHasuraSession.isDockerAvailable();
  if (!dockerReachable) {
    if (isPgTestsRequired()) {
      test('Docker is available for isolated Hasura', () {
        fail(
          'Docker required ($pgTestsRequiredEnvVar=1) but not available',
        );
      });
    } else {
      test('Docker unavailable', () {}, skip: 'Docker not available');
    }
    return;
  }

  group('Room participants through Hasura with a block', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late AuthCase authCase;
    late IsolatedHasuraSession hasura;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      for (final id in [_author, _forwarder, _recipient]) {
        await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', 'pk-$id')
''');
      }
      // The Post: author -> forwarder -> recipient. The forward-edge trigger
      // admits both recipients as addressees.
      await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES ('$_post', '$_author', '', '', 0, 1, 1, false, now())
''');
      await writer.execute('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES
  ('Fhroomgateedge1', '$_post', '$_author', '$_forwarder'),
  ('Fhroomgateedge2', '$_post', '$_forwarder', '$_recipient')
''');
      // The Request with the same people admitted to its room.
      await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, published_at)
VALUES ('$_request', '$_author', 'Request', '', 0, now())
''');
      await writer.execute('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES
  ('Fhroomgateedge3', '$_request', '$_author', '$_forwarder'),
  ('Fhroomgateedge4', '$_request', '$_forwarder', '$_recipient')
''');
      await writer.execute('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES
  ('Phroomgatereqf1', '$_request', '$_forwarder', 0, 0, 3),
  ('Phroomgatereqr1', '$_request', '$_recipient', 0, 0, 3)
''');

      final jwtKeys = loadJwtKeysForHasuraPgTests();
      authCase = AuthCase(
        _NoopUserRepository(),
        _NoopInvitationRepository(),
        env: _authEnv(target.databaseEnv, jwtKeys),
        logger: Logger('PostRoomBlockHasuraPgTest'),
      );
      hasura = await IsolatedHasuraSession.start(
        databaseEnv: target.databaseEnv,
        jwtPublicPem: jwtKeys.publicKey,
      );
      await hasura.applyRepoMetadata();
    });

    setUp(() => writer.execute('TRUNCATE TABLE public.user_block'));

    tearDownAll(() async {
      try {
        await hasura.stop();
      } finally {
        await tearDownDisposablePgWriter(session: session);
      }
    });

    Future<Set<String>> participantsSeenBy(
      String viewer,
      String beaconId,
    ) async {
      final response = await _graphql(
        hasura,
        authCase.issueAccessToken(viewer).rawToken,
        '''
query {
  beacon_participant(where: {beacon_id: {_eq: "$beaconId"}}) { user_id }
}
''',
      );
      expect(response['errors'], isNull, reason: response.toString());
      final rows =
          (response['data']! as Map<String, dynamic>)['beacon_participant']
              as List<dynamic>;
      return {
        for (final row in rows)
          (row as Map<String, dynamic>)['user_id']! as String,
      };
    }

    Future<void> block(String blocker, String blocked) => writer.execute('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$blocker', '$blocked', '$blocked')
''');

    test('Hasura accepts the repository metadata without dropping objects', () {
      return hasura.assertMetadataConsistent();
    });

    test(
      'without a block the Post member reads the other participants',
      () async {
        expect(
          await participantsSeenBy(_recipient, _post),
          equals({_forwarder, _recipient}),
        );
      },
    );

    test('the Post member loses the other participants when the author blocks '
        'them', () async {
      await block(_author, _recipient);

      expect(
        await participantsSeenBy(_recipient, _post),
        _noRowsBeyondOwn,
      );
    });

    test('the Post member loses the other participants when they block the '
        'author', () async {
      await block(_recipient, _author);

      expect(
        await participantsSeenBy(_recipient, _post),
        _noRowsBeyondOwn,
      );
    });

    test(
      'the forwarder keeps reading the Post participants after the block',
      () async {
        await block(_author, _recipient);

        expect(
          await participantsSeenBy(_forwarder, _post),
          equals({_forwarder, _recipient}),
        );
      },
    );

    test(
      'the author keeps reading the Post participants after the block',
      () async {
        await block(_author, _recipient);

        expect(
          await participantsSeenBy(_author, _post),
          equals({_forwarder, _recipient}),
        );
      },
    );

    for (final (label, blocker, blocked) in [
      ('the author blocks the member', _author, _recipient),
      ('the member blocks the author', _recipient, _author),
    ]) {
      test('the Request member still reads the other participants when '
          '$label', () async {
        await block(blocker, blocked);

        expect(
          await participantsSeenBy(_recipient, _request),
          equals({_forwarder, _recipient}),
        );
      });
    }
  });
}

Future<Map<String, dynamic>> _graphql(
  IsolatedHasuraSession hasura,
  String jwt,
  String query,
) async {
  final response = await http.post(
    Uri.parse('${hasura.baseUrl}/v1/graphql'),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $jwt',
    },
    body: jsonEncode({'query': query}),
  );
  return jsonDecode(response.body) as Map<String, dynamic>;
}

final class _NoopUserRepository implements UserRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _NoopInvitationRepository implements InvitationRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Env _authEnv(Env base, ({String publicKey, String privateKey}) jwtKeys) => Env(
  environment: base.environment,
  pgHost: base.pgHost,
  pgPort: base.pgPort,
  pgDatabase: base.pgDatabase,
  pgUsername: base.pgUsername,
  pgPassword: base.pgPassword,
  printEnv: false,
  isDebugModeOn: false,
  publicKey: jwtKeys.publicKey,
  privateKey: jwtKeys.privateKey,
);
