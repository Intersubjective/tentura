@Tags(['pg'])
library;

import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_attention.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';

import '../../../support/disposable_pg_target.dart';

const _viewer = 'Uhistorylifecycle';
const _beacon = 'Bhistorylifecycle';
const _receipt = 'Nhistorylifecycle';

// The wire contract is lifecycle eligibility, independent of clear/settlement
// and placement. Read persisted rows through the actual account History query;
// a constructed domain entity would bypass the missing SQL projection.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_HISTORY_LIFECYCLE_TEST_DB',
    defaultNamePrefix: 'tentura_test_history_lifecycle',
  );
  final skipReason = await pgSkipReason(target);

  group('History receipt lifecycle eligibility', () {
    late DisposablePgWriterSession session;
    late TenturaDb database;
    late QueryAttention queries;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      database = openDisposablePgDatabase(target);
      queries = QueryAttention(query: AttentionRepository(database));
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    for (final scenario in [
      (
        name: 'closed Post remains in All with lifecycle eligibility false',
        post: true,
        status: BeaconStatus.closed,
        eligible: false,
        expired: false,
        timelineOnly: false,
        cleared: false,
        settled: false,
      ),
      (
        name:
            'expired open Post remains in All with lifecycle eligibility false',
        post: true,
        status: BeaconStatus.open,
        eligible: false,
        expired: true,
        timelineOnly: false,
        cleared: false,
        settled: false,
      ),
      (
        name: 'open Post exposes lifecycle eligibility true',
        post: true,
        status: BeaconStatus.open,
        eligible: true,
        expired: false,
        timelineOnly: false,
        cleared: false,
        settled: false,
      ),
      (
        name: 'open Request exposes lifecycle eligibility true without a TTL',
        post: false,
        status: BeaconStatus.open,
        eligible: true,
        expired: false,
        timelineOnly: false,
        cleared: false,
        settled: false,
      ),
      (
        name: 'timeline-only Post receipt stays eligible and counted in Unread',
        post: true,
        status: BeaconStatus.open,
        eligible: true,
        expired: false,
        timelineOnly: true,
        cleared: false,
        settled: false,
      ),
      (
        name: 'cleared open Post stays lifecycle eligible outside Unread',
        post: true,
        status: BeaconStatus.open,
        eligible: true,
        expired: false,
        timelineOnly: false,
        cleared: true,
        settled: false,
      ),
      (
        name: 'settled Request stays lifecycle eligible outside Unread',
        post: false,
        status: BeaconStatus.open,
        eligible: true,
        expired: false,
        timelineOnly: false,
        cleared: false,
        settled: true,
      ),
      (
        name: 'cleared closed Post stays lifecycle ineligible outside Unread',
        post: true,
        status: BeaconStatus.closed,
        eligible: false,
        expired: false,
        timelineOnly: false,
        cleared: true,
        settled: false,
      ),
      (
        name: 'settled expired Post stays lifecycle ineligible outside Unread',
        post: true,
        status: BeaconStatus.open,
        eligible: false,
        expired: true,
        timelineOnly: false,
        cleared: false,
        settled: true,
      ),
      // Deleted Posts are excluded by visibility before History returns a row.
      // m0269 supplies a TTL for every open Post, so a missing-TTL open Post
      // cannot be produced through the current database write path.
    ]) {
      test(scenario.name, () async {
        final writer = session.writer;
        await writer.execute('''
TRUNCATE public.notification_outbox, public.beacon, public."user" CASCADE
''');
        await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$_viewer', 'History viewer', 'key-$_viewer')
''');
        await writer.execute(
          Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, kind, status, is_discoverable,
   published_at, expires_at)
VALUES (@id, @viewer, @title, '', @kind, @status, false, now(),
  CASE WHEN @post THEN now() + @hours * interval '1 hour' ELSE NULL END)
'''),
          parameters: {
            'id': _beacon,
            'viewer': _viewer,
            'title': scenario.post ? '' : 'Open Request',
            'kind':
                (scenario.post ? BeaconKind.post : BeaconKind.request).value,
            'status': scenario.status.smallintValue,
            'post': scenario.post,
            'hours': scenario.expired ? -2 : 2,
          },
        );
        await writer.execute(
          Sql.named('''
INSERT INTO public.notification_outbox
  (id, account_id, category, kind, priority, title, body, action_url,
   dedup_key, beacon_id, source_event_key, destination_kind,
   presentation_key, presentation_payload, suppression_class, access_policy,
   placement, requires_action, attention_thread_key, settlement_kind,
   settled_at, cleared_at, clear_reason)
VALUES
  (@id, @viewer, 'coordination', 'newRelay', 'normal',
   'Shared a post', 'Shared content', '/attention', @id, @beacon, @id,
   'beacon', 'relay_received', '{"eventType":"relayReceived"}'::jsonb,
   'standard', 'beacon_content', @placement, @settled,
   CASE WHEN @settled THEN 'v1|needsMe|Bhistorylifecycle|Uhistorylifecycle'
     ELSE NULL END,
   CASE WHEN @settled THEN 'resolved' ELSE NULL END,
   CASE WHEN @settled THEN now() ELSE NULL END,
   CASE WHEN @cleared THEN now() ELSE NULL END,
   CASE WHEN @cleared THEN 'explicit' ELSE NULL END)
'''),
          parameters: {
            'id': _receipt,
            'viewer': _viewer,
            'beacon': _beacon,
            'placement': scenario.timelineOnly ? 'timeline_only' : 'primary',
            'settled': scenario.settled,
            'cleared': scenario.cleared,
          },
        );

        final graphQL = GraphQL(
          GraphQLSchema(
            queryType: GraphQLObjectType('Query', null)
              ..fields.addAll([
                queries.attentionFeed,
                queries.attentionSurfaceSummary,
              ]),
          ),
        );
        Future<Map<dynamic, dynamic>> history({
          required bool includeEligibility,
        }) async {
          final eligibilitySelection = includeEligibility
              ? 'historyLifecycleEligible'
              : '';
          final response =
              await graphQL.parseAndExecute(
                    '{ '
                    'all: attentionFeed(view: "all") { '
                    'summary { unreadTotal } page { items { '
                    'id beaconId clearedAt settlementKind $eligibilitySelection } } } '
                    'unread: attentionFeed(view: "unread") { '
                    'summary { unreadTotal } page { items { '
                    'id $eligibilitySelection } } } '
                    'attentionSurfaceSummary { unreadTotal } '
                    '}',
                    globalVariables: {
                      kGlobalInputQueryJwt: const JwtEntity(sub: _viewer),
                    },
                  )
                  as Map;
          // graphql_server2 returns the selected data directly.
          return response;
        }

        final unread =
            scenario.eligible && !scenario.cleared && !scenario.settled;
        void expectHistory(
          Map<dynamic, dynamic> data, {
          required bool includeEligibility,
        }) {
          final all = data['all'] as Map;
          final allItems = (all['page'] as Map)['items'] as List;
          expect(allItems, hasLength(1));
          final row = allItems.single as Map;
          expect(row['id'], _receipt);
          expect(row['beaconId'], _beacon);
          expect(row['clearedAt'] != null, scenario.cleared);
          expect(row['settlementKind'], scenario.settled ? 'resolved' : null);
          final unreadFeed = data['unread'] as Map;
          final unreadItems = (unreadFeed['page'] as Map)['items'] as List;
          expect(
            unreadItems.map((item) => (item as Map)['id']),
            unread ? [_receipt] : isEmpty,
          );
          expect((all['summary'] as Map)['unreadTotal'], unread ? 1 : 0);
          expect((unreadFeed['summary'] as Map)['unreadTotal'], unread ? 1 : 0);
          expect(
            (data['attentionSurfaceSummary'] as Map)['unreadTotal'],
            unread ? 1 : 0,
          );
          if (includeEligibility) {
            expect(row['historyLifecycleEligible'], scenario.eligible);
            for (final item in unreadItems) {
              expect((item as Map)['historyLifecycleEligible'], isTrue);
            }
          }
        }

        // First prove the fixture and existing list/count behaviour through
        // GraphQL. Then select the new field over exactly the same real path.
        expectHistory(
          await history(includeEligibility: false),
          includeEligibility: false,
        );
        expectHistory(
          await history(includeEligibility: true),
          includeEligibility: true,
        );
      });
    }
  }, skip: skipReason);
}
