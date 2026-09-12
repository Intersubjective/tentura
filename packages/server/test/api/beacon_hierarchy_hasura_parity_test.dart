@Tags(['pg'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/port/invitation_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/env.dart';

import '../support/beacon_hierarchy_fixture.dart';
import '../support/isolated_hasura_session.dart';
import '../data/repository/beacon_hierarchy_pg_helpers.dart';

/// Hasura read-side parity for hierarchy predicates (Task 03).
///
/// Default `beacon` select permissions remain `can_read_content`-gated; this
/// test proves that contract is unchanged while computed fields exist for later
/// linked-detail projections (Task 10). Probes use real user-session JWTs.
Future<void> main() async {
  final postgresReachable = await canConnectBeaconHierarchyPostgres();
  final dockerReachable = postgresReachable && await IsolatedHasuraSession.isDockerAvailable();
  final skipReason = !postgresReachable
      ? 'Postgres admin database not reachable'
      : !dockerReachable
      ? 'Docker not available for isolated Hasura'
      : false;

  group('beacon hierarchy Hasura parity — disposable Postgres', () {
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
        logger: Logger('BeaconHierarchyHasuraParityTest'),
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

    Future<void> seedTreeAndAdmitFrankToA() async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);
      for (final row in <(String, String, String, int)>[
        ('PhieraliceA01', BeaconHierarchyTopology.beaconA, BeaconHierarchyTopology.aliceId, RoomAccessBits.admitted),
        ('PhierbobB01', BeaconHierarchyTopology.beaconB, BeaconHierarchyTopology.bobId, RoomAccessBits.admitted),
        ('PhiercarolC01', BeaconHierarchyTopology.beaconC, BeaconHierarchyTopology.carolId, RoomAccessBits.admitted),
        ('PhierfrankA01', BeaconHierarchyTopology.beaconA, BeaconHierarchyTopology.frankId, RoomAccessBits.admitted),
      ]) {
        await writer.execute(
          Sql.named(r'''
INSERT INTO public.beacon_participant (
  id, beacon_id, user_id, role, status, room_access, created_at, updated_at
) VALUES (
  @id, @beaconId, @userId, 0, 0, @roomAccess,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
ON CONFLICT (id) DO UPDATE SET room_access = EXCLUDED.room_access
'''),
          parameters: {
            'id': row.$1,
            'beaconId': row.$2,
            'userId': row.$3,
            'roomAccess': row.$4,
          },
        );
      }
    }

    test('metadata exposes linked-detail fields without parent relationships', () {
      final metadataFile = File(
        '${Directory.current.path}/../../hasura/metadata.json',
      );
      final metadata =
          jsonDecode(metadataFile.readAsStringSync()) as Map<String, dynamic>;
      final tables =
          (metadata['metadata'] as Map<String, dynamic>)['sources'][0]['tables']
              as List<dynamic>;
      final beaconTable = tables.cast<Map<String, dynamic>>().firstWhere(
        (entry) => (entry['table'] as Map<String, dynamic>)['name'] == 'beacon',
      );
      final computed =
          (beaconTable['computed_fields'] as List<dynamic>)
              .map((entry) => (entry as Map<String, dynamic>)['name'] as String)
              .toSet();
      expect(
        computed,
        containsAll(['can_read_linked_detail', 'effective_admission']),
      );

      final permission =
          (beaconTable['select_permissions'] as List<dynamic>).single
              as Map<String, dynamic>;
      final filter =
          (permission['permission'] as Map<String, dynamic>)['filter']
              as Map<String, dynamic>;
      expect(filter['can_read_content'], {'_eq': true});
      expect(
        (permission['permission'] as Map<String, dynamic>)['computed_fields'],
        isNot(contains('can_read_linked_detail')),
        reason: 'linked-detail tier is not exposed on the content select path',
      );

      final relationships =
          (beaconTable['object_relationships'] as List<dynamic>? ?? const [])
              .cast<Map<String, dynamic>>();
      final hierarchyRelNames = relationships
          .map((rel) => rel['name'] as String)
          .where((name) => name.contains('parent') || name.contains('child'))
          .toList();
      expect(hierarchyRelNames, isEmpty);
    });

    test(
      'JWT user cannot read child beacon row via unchanged content permission',
      () async {
        await seedTreeAndAdmitFrankToA();
        final jwt = authCase
            .issueAccessToken(BeaconHierarchyTopology.frankId)
            .rawToken;
        final childId = BeaconHierarchyTopology.beaconB;

        final byPk = await _queryBeaconByPk(
          hasuraUrl: hasura!.baseUrl,
          jwt: jwt,
          beaconId: childId,
          fields: 'id can_read_content',
        );
        expect(byPk, isNull, reason: 'content row filter must hide child B');

        final contentRows = await _queryBeacons(
          hasuraUrl: hasura!.baseUrl,
          jwt: jwt,
          where: '{can_read_content: {_eq: true}}',
          fields: 'id',
        );
        expect(
          contentRows.map((row) => row['id']),
          isNot(contains(childId)),
          reason: 'hierarchy-only viewer must not gain child content listing',
        );
      },
      skip: skipReason,
    );
  });
}

Future<List<Map<String, dynamic>>> _queryBeacons({
  required String hasuraUrl,
  required String jwt,
  required String where,
  required String fields,
}) async {
  final query = 'query { beacon(where: $where) { $fields } }';
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
  final rows = (body['data']! as Map<String, dynamic>)['beacon'] as List;
  return rows.cast<Map<String, dynamic>>();
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
      throw StateError('JWT_PUBLIC_PEM/JWT_PRIVATE_PEM required for Hasura JWT parity test');
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
    throw StateError('JWT_PUBLIC_PEM/JWT_PRIVATE_PEM required for Hasura JWT parity test');
  }
  return (publicKey: publicKey, privateKey: privateKey);
}
