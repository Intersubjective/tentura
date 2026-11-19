@Tags(['pg', 'mr', 'repo-files'])
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;

import '../../support/disposable_pg_target.dart';
import '../../support/hasura_pg_jwt_keys.dart';
import '../../support/isolated_hasura_session.dart';
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
  final pgSkip = await pgSkipReason(_target);
  final hasuraAvailable =
      pgSkip == null && await IsolatedHasuraSession.isDockerAvailable();
  final skipReason =
      pgSkip ?? (hasuraAvailable ? false : 'Docker not available');

  late TenturaDb db;
  late IsolatedHasuraSession hasura;
  if (skipReason == false) {
    setUpAll(() async {
      final session = await setUpDisposablePgWriter(
        target: _target,
        createPgmer2Extension: true,
      );
      addTearDown(() => tearDownDisposablePgWriter(session: session));
      db = openDisposablePgDatabase(_target);
      addTearDown(db.close);

      final jwt = loadJwtKeysForHasuraPgTests();
      hasura = await IsolatedHasuraSession.start(
        databaseEnv: _target.databaseEnv,
        jwtPublicPem: jwt.publicKey,
      );
      addTearDown(hasura.stop);
      await hasura.applyRepoMetadata();
      await hasura.assertMetadataConsistent();
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
      [
        id,
        status,
        isDiscoverable,
        effectivePublishedAt.toUtc().toIso8601String(),
      ],
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
        hasura,
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
        hasura,
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
          hasura,
          userId: 'Uibxvispeer1',
          beaconId: 'Bibxvisdisc1',
        ),
        isTrue,
      );
      expect(
        await _hasuraBeaconReadable(
          hasura,
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

Future<bool> _hasuraBeaconReadable(
  IsolatedHasuraSession hasura, {
  required String userId,
  required String beaconId,
  bool filtered = true,
}) async {
  final filter = filtered ? ', can_read_content: {_eq: true}' : '';
  final query =
      'query { beacon(where: {id: {_eq: "$beaconId"}$filter}) { id } }';
  final response = await http
      .post(
        Uri.parse('${hasura.baseUrl}/v1/graphql'),
        headers: {
          'Content-Type': 'application/json',
          'X-Hasura-Admin-Secret': hasura.adminSecret,
          'X-Hasura-Role': 'user',
          'X-Hasura-User-Id': userId,
        },
        body: jsonEncode({'query': query}),
      )
      .timeout(const Duration(seconds: 10));
  final body = jsonDecode(response.body) as Map<String, dynamic>;
  expect(body['errors'], isNull, reason: body.toString());
  final rows = (body['data']! as Map<String, dynamic>)['beacon'] as List;
  return rows.isNotEmpty;
}

Future<List<Map<String, dynamic>>> _queryInboxItem(
  IsolatedHasuraSession hasura, {
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
    Uri.parse('${hasura.baseUrl}/v1/graphql'),
    headers: {
      'Content-Type': 'application/json',
      'X-Hasura-Admin-Secret': hasura.adminSecret,
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

final _target = DisposablePgTarget.fromNamedEnvironment(
  envVarName: 'TENTURA_INBOX_BEACON_VISIBILITY_HASURA_TEST_DB',
  defaultNamePrefix: 'tentura_test_inbox_beacon_vis',
);
