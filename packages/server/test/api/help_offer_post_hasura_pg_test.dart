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

/// m0212: through a real Hasura, role `user` can offer help on a Request but
/// not on a Post.
/// See `docs/plans/post-and-constellation-composer-plan.md` §4.
const _author = 'Um0212hauthor01';
const _offerer = 'Um0212hoffer0001';

const _request = 'Bm0212hrequest01';
const _post = 'Bm0212hpost00001';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0212_HELP_OFFER_HASURA_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0212_hasura',
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

  group('Help offers on a Post through Hasura', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late AuthCase authCase;
    late IsolatedHasuraSession hasura;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      for (final id in [_author, _offerer]) {
        await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', 'pk-$id')
''');
      }
      await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, published_at)
VALUES ('$_request', '$_author', 'Request', '', 0, now())
''');
      await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES ('$_post', '$_author', '', '', 0, 1, 1, false, now())
''');
      // The offerer can read both beacons.
      await writer.execute('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES
  ('Fm0212hedge001', '$_request', '$_author', '$_offerer'),
  ('Fm0212hedge002', '$_post', '$_author', '$_offerer')
''');

      final jwtKeys = loadJwtKeysForHasuraPgTests();
      authCase = AuthCase(
        _NoopUserRepository(),
        _NoopInvitationRepository(),
        env: _authEnv(target.databaseEnv, jwtKeys),
        logger: Logger('HelpOfferPostHasuraPgTest'),
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

    test('role user can insert a help offer on a Request', () async {
      final response = await _graphql(
        hasura,
        authCase.issueAccessToken(_offerer).rawToken,
        _insertOffer(_request),
      );
      expect(response['errors'], isNull, reason: response.toString());

      final rows = await writer.execute('''
SELECT message FROM public.beacon_help_offer
WHERE beacon_id = '$_request' AND user_id = '$_offerer'
''');
      expect(rows.single[0], 'I can help');
    });

    test('role user cannot insert a help offer on a Post', () async {
      final response = await _graphql(
        hasura,
        authCase.issueAccessToken(_offerer).rawToken,
        _insertOffer(_post),
      );
      expect(response['errors'], isNotNull, reason: response.toString());

      final rows = await writer.execute('''
SELECT count(*) FROM public.beacon_help_offer
WHERE beacon_id = '$_post' AND user_id = '$_offerer'
''');
      expect(rows.single[0], 0);
    });
  });
}

String _insertOffer(String beaconId) =>
    '''
mutation {
  insert_beacon_help_offer_one(
    object: {beacon_id: "$beaconId", message: "I can help"}
  ) { beacon_id }
}
''';

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
