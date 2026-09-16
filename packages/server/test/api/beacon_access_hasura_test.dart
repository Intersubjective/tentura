@Tags(['pg'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/domain/port/invitation_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/env.dart';

import '../support/beacon_hierarchy_fixture.dart';
import '../support/isolated_hasura_session.dart';
import '../data/repository/beacon_hierarchy_pg_helpers.dart';

/// Issue-146 T07: `access_level` / `access_reasons` are exposed to the `user`
/// role on `beacon`. Probes use real user-session JWTs, not admin.
Future<void> main() async {
  final postgresReachable = await canConnectBeaconHierarchyPostgres();
  final dockerReachable = postgresReachable && await IsolatedHasuraSession.isDockerAvailable();
  final skipReason = !postgresReachable
      ? 'Postgres admin database not reachable'
      : !dockerReachable
      ? 'Docker not available for isolated Hasura'
      : false;

  group('beacon access level Hasura exposure — disposable Postgres', () {
    late BeaconHierarchyDisposablePgTarget target;
    late Connection writer;
    late BeaconHierarchyFixture fixture;
    late AuthCase authCase;
    IsolatedHasuraSession? hasura;
    var setupComplete = false;

    setUpAll(() async {
      if (skipReason != false) {
        return;
      }
      target = BeaconHierarchyDisposablePgTarget.fromEnvironment();
      final session = await openBeaconHierarchyPgSession(target);
      writer = session.writer;
      fixture = BeaconHierarchyFixture(writer: writer, db: session.db);
      final jwtKeys = _loadJwtKeysFromRepoDotEnv();
      authCase = AuthCase(
        _NoopUserRepository(),
        _NoopInvitationRepository(),
        env: _authEnvForHasura(target, jwtKeys),
        logger: Logger('BeaconAccessHasuraTest'),
      );
      final startedHasura = await IsolatedHasuraSession.start(
        databaseEnv: target.databaseEnv,
        jwtPublicPem: jwtKeys.publicKey,
      );
      await startedHasura.applyRepoMetadata();
      hasura = startedHasura;
      setupComplete = true;
    });

    tearDown(() async {
      if (skipReason != false) {
        return;
      }
      await fixture.tearDown();
    });

    tearDownAll(() async {
      if (skipReason != false || !setupComplete) {
        return;
      }
      try {
        await hasura?.stop();
      } finally {
        await fixture.db.close();
        await writer.close();
        await target.drop();
      }
    });

    const fields = 'access_level access_reasons can_read_involvement';

    test('forward recipient sees observer level with forwarded reason', () async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, created_at
) VALUES (
  'FaccfwdBdave01', @beaconId, @senderId, @recipientId,
  '2026-01-02T00:00:00Z'
)
ON CONFLICT DO NOTHING
'''),
        parameters: {
          'beaconId': BeaconHierarchyTopology.beaconB,
          'senderId': BeaconHierarchyTopology.bobId,
          'recipientId': BeaconHierarchyTopology.daveId,
        },
      );

      final row = await _queryBeaconByPk(
        hasuraUrl: hasura!.baseUrl,
        jwt: authCase.issueAccessToken(BeaconHierarchyTopology.daveId).rawToken,
        beaconId: BeaconHierarchyTopology.beaconB,
        fields: fields,
      );
      expect(row, {
        'access_level': 2,
        'access_reasons': 8,
        'can_read_involvement': true,
      });
    }, skip: skipReason);

    test('author sees author level with author reason only', () async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);

      final row = await _queryBeaconByPk(
        hasuraUrl: hasura!.baseUrl,
        jwt: authCase.issueAccessToken(BeaconHierarchyTopology.eveId).rawToken,
        beaconId: BeaconHierarchyTopology.beaconD,
        fields: fields,
      );
      expect(row, {
        'access_level': 0,
        'access_reasons': 1,
        'can_read_involvement': true,
      });
    }, skip: skipReason);
  });
}

Future<Map<String, dynamic>?> _queryBeaconByPk({
  required String hasuraUrl,
  required String jwt,
  required String beaconId,
  required String fields,
}) async {
  final query =
      'query { beacon_by_pk(id: "$beaconId") { $fields } }';
  final response = await http.post(
    Uri.parse('$hasuraUrl/v1/graphql'),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $jwt',
    },
    body: jsonEncode({'query': query}),
  );
  final body = jsonDecode(response.body) as Map<String, dynamic>;
  expect(body['errors'], isNull, reason: body.toString());
  return (body['data']! as Map<String, dynamic>)['beacon_by_pk']
      as Map<String, dynamic>?;
}

final class _NoopUserRepository implements UserRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _NoopInvitationRepository implements InvitationRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Env _authEnvForHasura(
  BeaconHierarchyDisposablePgTarget target,
  ({String publicKey, String privateKey}) jwtKeys,
) {
  final base = target.databaseEnv;
  return Env(
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
}

({String publicKey, String privateKey}) _loadJwtKeysFromRepoDotEnv() {
  final dotEnv = File('${Directory.current.path}/../../.env');
  if (!dotEnv.existsSync()) {
    final publicKey = Platform.environment['JWT_PUBLIC_PEM'];
    final privateKey = Platform.environment['JWT_PRIVATE_PEM'];
    if (publicKey == null || privateKey == null) {
      throw StateError('JWT_PUBLIC_PEM/JWT_PRIVATE_PEM required for Hasura access test');
    }
    return (publicKey: publicKey, privateKey: privateKey);
  }
  final values = <String, String>{};
  for (final line in dotEnv.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final idx = trimmed.indexOf('=');
    if (idx <= 0) continue;
    values[trimmed.substring(0, idx)] = trimmed
        .substring(idx + 1)
        .replaceAll(r'\n', '\n');
  }
  final publicKey = values['JWT_PUBLIC_PEM'] ?? Platform.environment['JWT_PUBLIC_PEM'];
  final privateKey = values['JWT_PRIVATE_PEM'] ?? Platform.environment['JWT_PRIVATE_PEM'];
  if (publicKey == null || privateKey == null) {
    throw StateError('JWT_PUBLIC_PEM/JWT_PRIVATE_PEM required for Hasura access test');
  }
  return (publicKey: publicKey, privateKey: privateKey);
}
