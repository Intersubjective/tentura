@Tags(['pg'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

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
  final hasuraReachable =
      postgresReachable && await _canConnectHasura();
  final skipReason = !postgresReachable
      ? 'local Postgres not reachable'
      : !hasuraReachable
          ? 'local Hasura not reachable'
          : false;

  late TenturaDb db;

  if (skipReason == false) {
    setUpAll(() async {
      db = TenturaDb(_testEnv());
    });

    tearDownAll(() async {
      await db.close();
    });

    tearDown(() async {
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

  Future<void> seedBeacon(String id, {required int status}) async {
    await db.customStatement(
      r'''
INSERT INTO public.beacon (id, user_id, title, description, status, created_at, updated_at)
VALUES ($1, 'Uibxvisauth', 'Inbox visibility beacon', '', $2, now(), now())
ON CONFLICT (id) DO UPDATE SET status = EXCLUDED.status
''',
      [id, status],
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
}

final _hasuraUrl =
    Platform.environment['HASURA_URL'] ?? 'http://127.0.0.1:8080';
final _hasuraAdminSecret =
    Platform.environment['HASURA_GRAPHQL_ADMIN_SECRET'] ?? 'password';

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

Env _testEnv() => Env(
      environment: Environment.test,
      pgHost: Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1',
      pgPort: int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432,
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
