@Tags(['pg', 'repo-files'])
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

/// Through a real Hasura, role `user` reads `expires_at` of a Post they are a
/// member of (an addressee). See `docs/plans/post-ttl-implementation-plan.md`.
const _author = 'Uttlexpauthor001';
const _member = 'Uttlexpmember001';
const _post = 'Bttlexppost00001';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_HASURA_BEACON_EXPIRES_AT_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_hasura_expires_at',
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

  group('Post expires_at through Hasura', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late AuthCase authCase;
    late IsolatedHasuraSession hasura;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      for (final id in [_author, _member]) {
        await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', 'pk-$id')
''');
      }
      await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at, expires_at)
VALUES
  ('$_post', '$_author', '', '', 0, 1, 1, false, now(),
   now() + interval '48 hours')
''');
      // Admits the member as an addressee of the Post.
      await writer.execute('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES ('Fttlexpedge0001', '$_post', '$_author', '$_member')
''');

      final jwtKeys = loadJwtKeysForHasuraPgTests();
      authCase = AuthCase(
        _NoopUserRepository(),
        _NoopInvitationRepository(),
        env: _authEnv(target.databaseEnv, jwtKeys),
        logger: Logger('HasuraBeaconExpiresAtPgTest'),
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

    test('a Post member reads the expires_at of the Post', () async {
      final response = await _graphql(
        hasura,
        authCase.issueAccessToken(_member).rawToken,
        'query { beacon_by_pk(id: "$_post") { id expires_at } }',
      );
      expect(response['errors'], isNull, reason: response.toString());
      final row =
          (response['data']! as Map<String, dynamic>)['beacon_by_pk']
              as Map<String, dynamic>?;
      expect(row, isNotNull);
      expect(row!['expires_at'], isNotNull);
    });
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
