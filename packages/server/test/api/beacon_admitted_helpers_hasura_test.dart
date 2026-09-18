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

/// m0174: admitted_helpers nested under beacon for content viewers;
/// involvement-gated help_offer.message stays closed for discover observers.
Future<void> main() async {
  final postgresReachable = await canConnectBeaconHierarchyPostgres();
  final dockerReachable =
      postgresReachable && await IsolatedHasuraSession.isDockerAvailable();
  final skipReason = !postgresReachable
      ? 'Postgres admin database not reachable'
      : !dockerReachable
      ? 'Docker not available for isolated Hasura'
      : false;

  group('beacon admitted helpers Hasura — disposable Postgres', () {
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
        logger: Logger('BeaconAdmittedHelpersHasuraTest'),
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

    test(
      'discover observer sees admitted helpers; blocked helper omitted; offer message denied',
      () async {
        await fixture.seedFullTopology();
        await seedPublishedHierarchyTree(writer);

        final beaconId = BeaconHierarchyTopology.beaconB;
        final author = BeaconHierarchyTopology.bobId;
        final discoverer = BeaconHierarchyTopology.frankId;
        final helper = BeaconHierarchyTopology.carolId;
        final blockedHelper = BeaconHierarchyTopology.daveId;

        await writer.execute(
          Sql.named(r'''
INSERT INTO public.beacon_participant (
  id, beacon_id, user_id, role, status, room_access, created_at, updated_at
) VALUES
  ('Pahlhasura01', @beaconId, @helper, 2, 5, @access, now(), now()),
  ('Pahlhasura02', @beaconId, @blocked, 2, 5, @access, now(), now())
ON CONFLICT (beacon_id, user_id) DO UPDATE SET
  room_access = EXCLUDED.room_access,
  role = EXCLUDED.role
'''),
          parameters: {
            'beaconId': beaconId,
            'helper': helper,
            'blocked': blockedHelper,
            'access': RoomAccessBits.admitted,
          },
        );

        // Discover path: mutual votes + discoverable.
        await writer.execute(
          Sql.named(r'''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES
  (@a, @b, 1, now(), now()),
  (@b, @a, 1, now(), now())
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
'''),
          parameters: {'a': author, 'b': discoverer},
        );
        await writer.execute(
          Sql.named(
            'UPDATE public.beacon SET is_discoverable = true WHERE id = @id',
          ),
          parameters: {'id': beaconId},
        );

        // Viewer blocks one helper.
        await writer.execute(
          Sql.named(r'''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id, created_at)
VALUES (@blocker, @blocked, @blocked, now())
ON CONFLICT DO NOTHING
'''),
          parameters: {'blocker': discoverer, 'blocked': blockedHelper},
        );

        final jwt = authCase.issueAccessToken(discoverer).rawToken;
        final row = await _gql(
          hasuraUrl: hasura!.baseUrl,
          jwt: jwt,
          query: '''
query {
  beacon_by_pk(id: "$beaconId") {
    can_read_admitted_helpers
    can_read_involvement
    admitted_helpers(order_by: {user_id: asc}) { user_id }
    admitted_helpers_aggregate { aggregate { count } }
  }
}
''',
        );
        final beacon = row['beacon_by_pk'] as Map<String, dynamic>;
        expect(beacon['can_read_admitted_helpers'], isTrue);
        expect(beacon['can_read_involvement'], isFalse);
        final helpers = (beacon['admitted_helpers'] as List)
            .map((e) => (e as Map)['user_id'] as String)
            .toList();
        expect(helpers, contains(helper));
        expect(helpers, isNot(contains(blockedHelper)));
        expect(
          (beacon['admitted_helpers_aggregate']
              as Map)['aggregate']['count'],
          helpers.length,
        );

        final offerProbe = await _gql(
          hasuraUrl: hasura!.baseUrl,
          jwt: jwt,
          query: '''
query {
  beacon_help_offer(where: {beacon_id: {_eq: "$beaconId"}}) {
    user_id
    message
  }
}
''',
          expectErrors: true,
        );
        // Either empty (filter denied) or GraphQL field/permission error —
        // never return offer messages to a discover-only observer.
        final offers = offerProbe['beacon_help_offer'];
        if (offers is List) {
          expect(offers, isEmpty);
        }
      },
      skip: skipReason,
    );
  });
}

Future<Map<String, dynamic>> _gql({
  required String hasuraUrl,
  required String jwt,
  required String query,
  bool expectErrors = false,
}) async {
  final response = await http.post(
    Uri.parse('$hasuraUrl/v1/graphql'),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $jwt',
    },
    body: jsonEncode({'query': query}),
  );
  final body = jsonDecode(response.body) as Map<String, dynamic>;
  if (!expectErrors) {
    expect(body['errors'], isNull, reason: body.toString());
  }
  return (body['data'] as Map<String, dynamic>?) ?? const {};
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
      throw StateError(
        'JWT_PUBLIC_PEM/JWT_PRIVATE_PEM required for Hasura access test',
      );
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
  final publicKey =
      values['JWT_PUBLIC_PEM'] ?? Platform.environment['JWT_PUBLIC_PEM'];
  final privateKey =
      values['JWT_PRIVATE_PEM'] ?? Platform.environment['JWT_PRIVATE_PEM'];
  if (publicKey == null || privateKey == null) {
    throw StateError(
      'JWT_PUBLIC_PEM/JWT_PRIVATE_PEM required for Hasura access test',
    );
  }
  return (publicKey: publicKey, privateKey: privateKey);
}
