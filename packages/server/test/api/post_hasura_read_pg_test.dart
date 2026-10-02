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

/// m0211: through a real Hasura, role `user` reads `viewer_can_forward` and the
/// Post columns on `beacon`, and `pinned_at` on `beacon_pinned`.
/// See `docs/plans/post-and-constellation-composer-plan.md` §4.3, §4.11.
const _author = 'Um0211hauthor01';
const _recipient = 'Um0211hrecip001';

/// Post whose `forward_policy` is closed (0): only the author may forward it.
/// Posts are always in an open-family status (`beacon_post_shape_ck`).
const _closedPost = 'Bm0211hclosed01';
const _openPost = 'Bm0211hopen0001';

/// Request in status closed (6) with the open policy: nobody may forward it.
const _finishedRequest = 'Bm0211hfinish01';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0211_POST_HASURA_READ_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0211_hasura',
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

  group('Post read model through Hasura', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late AuthCase authCase;
    late IsolatedHasuraSession hasura;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      for (final id in [_author, _recipient]) {
        await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', 'pk-$id')
''');
      }
      await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES
  ('$_closedPost', '$_author', '', '', 0, 1, 0, false, now()),
  ('$_openPost', '$_author', '', '', 0, 1, 1, false, now())
''');
      await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, published_at)
VALUES ('$_finishedRequest', '$_author', 'Finished', '', 6, now())
''');
      // Admits the recipient as an addressee of both Posts.
      await writer.execute('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES
  ('Fm0211hedge001', '$_closedPost', '$_author', '$_recipient'),
  ('Fm0211hedge002', '$_openPost', '$_author', '$_recipient')
''');
      await writer.execute('''
INSERT INTO public.beacon_pinned (user_id, beacon_id)
VALUES ('$_recipient', '$_closedPost')
''');

      final jwtKeys = loadJwtKeysForHasuraPgTests();
      authCase = AuthCase(
        _NoopUserRepository(),
        _NoopInvitationRepository(),
        env: _authEnv(target.databaseEnv, jwtKeys),
        logger: Logger('PostHasuraReadPgTest'),
      );
      hasura = await IsolatedHasuraSession.start(
        databaseEnv: target.databaseEnv,
        jwtPublicPem: jwtKeys.publicKey,
      );
      await hasura.applyRepoMetadata();
    });

    tearDownAll(() async {
      try {
        await hasura.stop();
      } finally {
        await tearDownDisposablePgWriter(session: session);
      }
    });

    test('Hasura accepts the repository metadata without dropping objects', () {
      return hasura.assertMetadataConsistent();
    });

    test(
      'a recipient of a closed Post reads viewer_can_forward false',
      () async {
        final row = await _beaconByPk(
          hasura,
          authCase.issueAccessToken(_recipient).rawToken,
          _closedPost,
          'viewer_can_forward',
        );
        expect(row, {'viewer_can_forward': false});
      },
    );

    test('the author of a closed Post reads viewer_can_forward true', () async {
      final row = await _beaconByPk(
        hasura,
        authCase.issueAccessToken(_author).rawToken,
        _closedPost,
        'viewer_can_forward',
      );
      expect(row, {'viewer_can_forward': true});
    });

    test(
      'the author of a finished Request reads viewer_can_forward false',
      () async {
        final row = await _beaconByPk(
          hasura,
          authCase.issueAccessToken(_author).rawToken,
          _finishedRequest,
          'viewer_can_forward',
        );
        expect(row, {'viewer_can_forward': false});
      },
    );

    test('a recipient of an open Post reads viewer_can_forward true', () async {
      final row = await _beaconByPk(
        hasura,
        authCase.issueAccessToken(_recipient).rawToken,
        _openPost,
        'viewer_can_forward',
      );
      expect(row, {'viewer_can_forward': true});
    });

    test('kind, forward_policy and last_activity_at are selectable', () async {
      final row = await _beaconByPk(
        hasura,
        authCase.issueAccessToken(_recipient).rawToken,
        _closedPost,
        'kind forward_policy last_activity_at post_root_message_id',
      );
      expect(row, isNotNull);
      expect(row!['kind'], 1);
      expect(row['forward_policy'], 0);
      expect(row['last_activity_at'], isNotNull);
      expect(row['post_root_message_id'], isNull);
    });

    test('a pin exposes pinned_at to its owner', () async {
      final response = await _graphql(
        hasura,
        authCase.issueAccessToken(_recipient).rawToken,
        'query { beacon_pinned { beacon_id pinned_at } }',
      );
      expect(response['errors'], isNull, reason: response.toString());
      final rows =
          (response['data']! as Map<String, dynamic>)['beacon_pinned']
              as List<dynamic>;
      expect(rows, hasLength(1));
      expect((rows.single as Map<String, dynamic>)['pinned_at'], isNotNull);
    });
  });
}

Future<Map<String, dynamic>?> _beaconByPk(
  IsolatedHasuraSession hasura,
  String jwt,
  String beaconId,
  String fields,
) async {
  final response = await _graphql(
    hasura,
    jwt,
    'query { beacon_by_pk(id: "$beaconId") { $fields } }',
  );
  expect(response['errors'], isNull, reason: response.toString());
  return (response['data']! as Map<String, dynamic>)['beacon_by_pk']
      as Map<String, dynamic>?;
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
