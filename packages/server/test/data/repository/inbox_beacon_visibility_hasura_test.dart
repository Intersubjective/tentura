@Tags(['pg'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/env.dart';

import '../../support/pg_test_public_keys.dart';

/// Hasura returns `beacon: null` for an `inbox_item` row whose beacon fails
/// the `can_read_content` row permission (e.g. the viewer's own beacon after
/// they delete it — deleted content is hidden even from its author). The
/// client's generated GraphQL model force-unwraps that field as non-null, so
/// an unfiltered InboxFetch crashes the whole projection and the Inbox screen
/// gets stuck (reported as an empty inbox stuck on its loading spinner).
///
/// `inbox_fetch.graphql` guards against this with
/// `where: {beacon: {can_read_content: {_eq: true}}}` (same pattern already
/// used by `profile_shared_beacons_fetch.graphql` /
/// `beacons_fetch_by_user_id.graphql`). This test locks in that Hasura-level
/// contract directly, since it cannot be exercised by a pure Dart unit test.
Future<void> main() async {
  final postgresReachable = await _canConnectPostgres();
  final hasuraReachable = postgresReachable && await _canConnectHasura();
  final skipReason = !postgresReachable
      ? 'local Postgres not reachable'
      : !hasuraReachable
      ? 'local Hasura not reachable'
      : false;

  late TenturaDb db;
  Map<String, dynamic>? originalHasuraSourceConfiguration;

  if (skipReason == false) {
    setUpAll(() async {
      final env = _testEnv();
      final writer = await Connection.open(
        env.pgEndpoint,
        settings: env.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await writer.execute('CREATE EXTENSION IF NOT EXISTS pgmer2');
      await migrateDbSchema(writer);
      await writer.close();
      db = TenturaDb(env);
      originalHasuraSourceConfiguration = await _pointHasuraAtTestDatabase();
    });

    tearDownAll(() async {
      try {
        await _restoreHasuraSourceConfiguration(
          originalHasuraSourceConfiguration,
        );
      } finally {
        await db.close();
      }
    });

    tearDown(() async {
      await db.customStatement(
        "DELETE FROM public.vote_user WHERE subject LIKE 'Uibxvis%' OR object LIKE 'Uibxvis%'",
      );
      await db.customStatement(
        "DELETE FROM public.inbox_item WHERE beacon_id LIKE 'Bibxvis%'",
      );
      await db.customStatement(
        "DELETE FROM public.beacon WHERE id LIKE 'Bibxvis%'",
      );
      await db.customStatement(
        '''DELETE FROM public."user" WHERE id LIKE 'Uibxvis%' ''',
      );
    });
  }

  Future<void> seedUser() async {
    await db.customStatement(
      r'''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('Uibxvisauth', 'Author', $1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name
''',
      [pgTestPublicKey('ibxvis', 1)],
    );
  }

  Future<void> seedBeacon(
    String id, {
    required int status,
    bool isDiscoverable = true,
    DateTime? publishedAt,
  }) async {
    final effectivePublishedAt = publishedAt ?? DateTime.utc(2026, 1, 1);
    await db.customStatement(
      r'''
INSERT INTO public.beacon (
  id, user_id, title, description, status, is_discoverable,
  published_at, created_at, updated_at
)
VALUES ($1, 'Uibxvisauth', 'Inbox visibility beacon', '', $2, $3, $4::timestamptz, now(), now())
ON CONFLICT (id) DO UPDATE SET
  status = EXCLUDED.status,
  is_discoverable = EXCLUDED.is_discoverable,
  published_at = EXCLUDED.published_at
''',
      [id, status, isDiscoverable, effectivePublishedAt.toUtc().toIso8601String()],
    );
  }

  Future<void> seedInboxItem(String beaconId) async {
    await db.customStatement(
      r'''
INSERT INTO public.inbox_item (
  user_id, beacon_id, context, forward_count, latest_forward_at, latest_note_preview
) VALUES ('Uibxvisauth', $1, 'test', 0, now(), '')
ON CONFLICT (user_id, beacon_id) DO NOTHING
''',
      [beaconId],
    );
  }

  test(
    'beacon.can_read_content filter drops an unreadable beacon and keeps the rest',
    () async {
      await seedUser();
      await seedBeacon(
        'Bibxvislive1',
        status: BeaconStatus.open.smallintValue,
      );
      await seedBeacon(
        'Bibxvisgone1',
        status: BeaconStatus.deleted.smallintValue,
      );
      await seedInboxItem('Bibxvislive1');
      await seedInboxItem('Bibxvisgone1');

      final unfiltered = await _queryInboxItem(
        userId: 'Uibxvisauth',
        filtered: false,
      );
      final goneRowUnfiltered = unfiltered.firstWhere(
        (row) => row['beacon_id'] == 'Bibxvisgone1',
      );
      expect(
        goneRowUnfiltered['beacon'],
        isNull,
        reason:
            'sanity: Hasura returns beacon:null for the deleted (unreadable) '
            'beacon instead of erroring — this is exactly what crashes the '
            "client's non-nullable generated model",
      );

      final filtered = await _queryInboxItem(
        userId: 'Uibxvisauth',
        filtered: true,
      );
      expect(
        filtered.map((row) => row['beacon_id']),
        ['Bibxvislive1'],
      );
    },
    skip: skipReason,
  );

  test(
    'Hasura beacon filter matches SQL discoverability for mutual peer',
    () async {
      await seedUser();
      await db.customStatement(
        r'''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('Uibxvispeer1', 'Peer', $1, now(), now())
ON CONFLICT (id) DO NOTHING
''',
        [pgTestPublicKey('ibxvis', 2)],
      );
      await db.customStatement(
        '''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES
  ('Uibxvispeer1', 'Uibxvisauth', 1, now(), now()),
  ('Uibxvisauth', 'Uibxvispeer1', 1, now(), now())
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
''',
      );
      await seedBeacon(
        'Bibxvisdisc1',
        status: BeaconStatus.open.smallintValue,
      );
      await seedInboxItem('Bibxvisdisc1');

      final sqlVisible = await db.customSelect(
        r'''
SELECT public.beacon_can_read_content('Bibxvisdisc1', 'Uibxvispeer1') AS ok
''',
      ).getSingle();
      expect(sqlVisible.read<bool>('ok'), isTrue);

      expect(
        await _hasuraBeaconReadable(
          userId: 'Uibxvispeer1',
          beaconId: 'Bibxvisdisc1',
        ),
        isTrue,
      );
      expect(
        await _hasuraBeaconReadable(
          userId: 'Uibxvispeer1',
          beaconId: 'Bibxvisdisc1',
          filtered: false,
        ),
        isTrue,
      );
    },
    skip: skipReason,
  );
}

final _hasuraUrl =
    Platform.environment['HASURA_URL'] ?? 'http://127.0.0.1:8080';
final _hasuraAdminSecret =
    Platform.environment['HASURA_GRAPHQL_ADMIN_SECRET'] ?? 'password';

Future<bool> _hasuraBeaconReadable({
  required String userId,
  required String beaconId,
  bool filtered = true,
}) async {
  final filter = filtered
      ? ', can_read_content: {_eq: true}'
      : '';
  final query =
      'query { beacon(where: {id: {_eq: "$beaconId"}$filter}) { id } }';
  final response = await http.post(
    Uri.parse('$_hasuraUrl/v1/graphql'),
    headers: {
      'Content-Type': 'application/json',
      'X-Hasura-Admin-Secret': _hasuraAdminSecret,
      'X-Hasura-Role': 'user',
      'X-Hasura-User-Id': userId,
    },
    body: jsonEncode({'query': query}),
  ).timeout(const Duration(seconds: 10));
  final body = jsonDecode(response.body) as Map<String, dynamic>;
  expect(body['errors'], isNull, reason: body.toString());
  final rows = (body['data']! as Map<String, dynamic>)['beacon'] as List;
  return rows.isNotEmpty;
}

Future<List<Map<String, dynamic>>> _queryInboxItem({
  required String userId,
  required bool filtered,
}) async {
  final where = filtered
      ? ', where: {beacon: {can_read_content: {_eq: true}}}'
      : '';
  final query =
      'query { inbox_item(order_by: {latest_forward_at: desc}$where) '
      '{ beacon_id beacon { id } } }';
  final response = await http.post(
    Uri.parse('$_hasuraUrl/v1/graphql'),
    headers: {
      'Content-Type': 'application/json',
      'X-Hasura-Admin-Secret': _hasuraAdminSecret,
      'X-Hasura-Role': 'user',
      'X-Hasura-User-Id': userId,
    },
    body: jsonEncode({'query': query}),
  );
  final body = jsonDecode(response.body) as Map<String, dynamic>;
  expect(body['errors'], isNull, reason: body.toString());
  final rows = (body['data']! as Map<String, dynamic>)['inbox_item'] as List;
  return rows.cast<Map<String, dynamic>>();
}

/// The tagged suite runs against an isolated database. Hasura is a separate
/// process, however, and its configured source normally remains the local
/// `postgres` database. Point it at the same disposable database for this
/// metadata/permission test, then restore its prior source configuration.
///
/// This is intentionally a no-op for the ordinary local `postgres` target so
/// developers can run the test without changing their Hasura configuration.
Future<Map<String, dynamic>?> _pointHasuraAtTestDatabase() async {
  final database = _testEnv().pgDatabase;
  if (database == 'postgres') return null;

  final metadata = await _postHasuraMetadata('export_metadata');
  final sources = metadata['sources']! as List;
  final source = sources.cast<Map<String, dynamic>>().singleWhere(
    (source) => source['name'] == 'postgres',
  );
  final original = Map<String, dynamic>.from(
    source['configuration']! as Map<String, dynamic>,
  );
  final connectionInfo = Map<String, dynamic>.from(
    original['connection_info']! as Map<String, dynamic>,
  )..['database_url'] = _hasuraTestDatabaseUrl(database);

  await _postHasuraMetadata(
    'pg_update_source',
    args: {
      'name': 'postgres',
      'configuration': {'connection_info': connectionInfo},
    },
  );
  return original;
}

Future<void> _restoreHasuraSourceConfiguration(
  Map<String, dynamic>? configuration,
) async {
  if (configuration == null) return;
  await _postHasuraMetadata(
    'pg_update_source',
    args: {'name': 'postgres', 'configuration': configuration},
  );
}

String _hasuraTestDatabaseUrl(String database) {
  final configured = Platform.environment['HASURA_TEST_DATABASE_URL'];
  if (configured != null && configured.isNotEmpty) return configured;

  return Uri(
    scheme: 'postgres',
    userInfo:
        '${Platform.environment['POSTGRES_USERNAME'] ?? 'postgres'}:'
        '${Platform.environment['POSTGRES_PASSWORD'] ?? 'password'}',
    host: Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1',
    port: int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432,
    path: database,
  ).toString();
}

Future<Map<String, dynamic>> _postHasuraMetadata(
  String type, {
  Map<String, dynamic> args = const {},
}) async {
  final response = await http.post(
    Uri.parse('$_hasuraUrl/v1/metadata'),
    headers: {
      'Content-Type': 'application/json',
      'X-Hasura-Admin-Secret': _hasuraAdminSecret,
    },
    body: jsonEncode({'type': type, 'args': args}),
  );
  final body = jsonDecode(response.body) as Map<String, dynamic>;
  expect(response.statusCode, 200, reason: body.toString());
  expect(body['error'], isNull, reason: body.toString());
  return body;
}

Env _testEnv() => Env(
  environment: Environment.test,
  pgHost: Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1',
  pgPort: int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432,
  pgDatabase: Platform.environment['POSTGRES_DBNAME'] ?? 'postgres',
  pgPassword: Platform.environment['POSTGRES_PASSWORD'] ?? 'password',
  printEnv: false,
  isDebugModeOn: false,
);

Future<bool> _canConnectPostgres() async {
  try {
    final db = TenturaDb(_testEnv());
    await db.customSelect('SELECT 1').getSingle();
    await db.close();
    return true;
  } on Object catch (_) {
    return false;
  }
}

Future<bool> _canConnectHasura() async {
  try {
    final response = await http
        .post(
          Uri.parse('$_hasuraUrl/v1/graphql'),
          headers: {
            'Content-Type': 'application/json',
            'X-Hasura-Admin-Secret': _hasuraAdminSecret,
          },
          body: jsonEncode({'query': '{ __typename }'}),
        )
        .timeout(const Duration(seconds: 2));
    return response.statusCode == 200;
  } on Object catch (_) {
    return false;
  }
}
