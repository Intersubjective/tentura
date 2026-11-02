@Tags(['perf', 'pg', 'mr'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart' as pg;
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/query/query_attention.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/api/controllers/graphql_controller.dart';
import 'package:tentura_server/api/http/request_context_io_adapter.dart';
import 'package:tentura_server/data/database/main_db_pool.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/request_context.dart';
import 'package:tentura_server/env.dart';

import '../support/disposable_pg_target.dart';
import '../support/meritrank_lock_probe.dart';
import '../support/pg_test_public_keys.dart';

const _runs = 20;
const _historyBeacons = 128;
const _historyReceiptsPerBeacon = 128;
const _historyHeavy = 'Ufeedscaleheavy';
const _historyTypical = 'Ufeedscaletypical';
const _document = r'''
query AttentionFeed($surface: String) {
  attentionFeed(view: "all", limit: 50, surface: $surface) {
    summary { unreadTotal needsYouTotal }
    page { items { id } nextCursor }
  }
}
''';

/// Local dataset measurements, never production/dev-host benchmarks. Each
/// source remains untouched: only its disposable clone is migrated to head.
/// The guard uses the real HTTP resolver and its request-scoped SQL deadline.
Future<void> main() async {
  for (final dataset in [
    (source: 'tentura_devcopy', largeHistory: false),
    (source: 'tentura_perfsynth', largeHistory: false),
    (source: 'tentura_perfsynth', largeHistory: true),
  ]) {
    final source = dataset.source;
    final label = dataset.largeHistory
        ? '$source with large receipt history'
        : source;
    for (final surface in <String?>[null, 'activity']) {
      test(
        'heavy and typical viewers receive their feed with p95 below half '
        'the statement deadline on $label with surface ${surface ?? 'history'}',
        () async {
          final target = DisposablePgTarget.fromNamedEnvironment(
            envVarName: 'TENTURA_ATTENTION_FEED_BUDGET_TEST_DB',
            defaultNamePrefix: 'tentura_test_feed_budget',
          );
          expect(
            target.adminEnv.pgHost,
            isIn(['127.0.0.1', 'localhost', '::1']),
            reason: 'Dataset performance measurements must run locally.',
          );
          final exclusive = await holdMeritRankSuiteLock(target);
          addTearDown(exclusive.close);
          final admin = await pg.Connection.open(
            target.adminEnv.pgEndpoint,
            settings: target.adminEnv.pgEndpointSettings,
          );
          try {
            await withDisposablePgLifecycleLock(target.adminEnv, () async {
              await admin.execute(
                'CREATE DATABASE "${target.databaseName}" TEMPLATE "$source"',
              );
            });
          } finally {
            await admin.close();
          }
          addTearDown(target.drop);
          final writer = await pg.Connection.open(
            target.databaseEnv.pgEndpoint,
            settings: target.databaseEnv.pgEndpointSettings,
          );
          addTearDown(writer.close);
          await migrateDbSchema(writer);
          if (dataset.largeHistory) await _seedLargeReceiptHistory(writer);
          final env = Env(
            environment: Environment.test,
            printEnv: false,
            isDebugModeOn: false,
            pgHost: target.databaseEnv.pgHost,
            pgPort: target.databaseEnv.pgPort,
            pgDatabase: target.databaseName,
            pgUsername: target.databaseEnv.pgUsername,
            pgPassword: target.databaseEnv.pgPassword,
          );
          final pool = MainDbPool(env);
          addTearDown(pool.close);
          final capture = _FeedStatements();
          final database = TenturaDb.scoped(
            pool,
            scopeInterceptor: () => capture,
          );
          addTearDown(database.close);
          final controller = GraphqlController(
            env,
            schema: TenturaGraphQL(
              GraphQLSchema(
                queryType: GraphQLObjectType('Query', 'Query root')
                  ..fields.add(
                    QueryAttention(
                      query: AttentionRepository(database),
                    ).attentionFeed,
                  ),
              ),
            ),
          );
          final viewers = await writer.execute('''
SELECT account_id, count(*)::int AS receipts
FROM public.notification_outbox
GROUP BY account_id
ORDER BY receipts DESC, account_id
''');
          expect(
            viewers,
            isNotEmpty,
            reason: 'The dataset must contain receipts.',
          );
          final population = await writer.execute(
            'SELECT count(*)::int FROM public.notification_outbox',
          );
          final selected = {
            'heavy': viewers.first,
            'typical': dataset.largeHistory
                ? viewers.singleWhere((row) => row[0] == _historyTypical)
                : viewers[viewers.length ~/ 2],
          };
          for (final entry in selected.entries) {
            final viewer = entry.value[0]! as String;
            final expectedRows = await writer.execute(
              r'''
SELECT visible.receipt_id
FROM public.visible_attention_receipts($1) visible
ORDER BY (visible.receipt).created_at DESC, visible.receipt_id DESC
LIMIT 51
''',
              parameters: [viewer],
            );
            final expectedIds = expectedRows
                .take(50)
                .map((row) => row[0]! as String)
                .toList();
            expect(
              expectedIds,
              isNotEmpty,
              reason:
                  'The selected ${entry.key} viewer must have a visible feed.',
            );
            final handler = requestContextIoAdapter((request) {
              return controller.handler(
                request.change(
                  context: {kContextJwtKey: JwtEntity(sub: viewer)},
                ),
              );
            });
            final request = RequestContext(requestId: 'feed-budget');
            final deadlineMs = min(
              env.pgStatementTimeoutMs,
              request.remaining.inMilliseconds,
            );
            request.dispose();
            capture.samples.clear();
            for (var run = 0; run < _runs; run++) {
              final response = await handler(
                Request(
                  'POST',
                  Uri.parse('http://localhost/api/v2/graphql'),
                  headers: {'content-type': 'application/json'},
                  body: jsonEncode({
                    'query': _document,
                    'operationName': 'AttentionFeed',
                    if (surface != null) 'variables': {'surface': surface},
                  }),
                ),
              );
              expect(response.statusCode, 200);
              final payload = jsonDecode(await response.readAsString()) as Map;
              expect(payload['errors'], isNull, reason: jsonEncode(payload));
              final feed = (payload['data']! as Map)['attentionFeed']! as Map;
              final page = feed['page']! as Map;
              if (surface == null) {
                expect(
                  (page['items']! as List).map((item) => (item as Map)['id']),
                  orderedEquals(expectedIds),
                );
                expect(page['nextCursor'] != null, expectedRows.length > 50);
              } else {
                expect(page['items'], isA<List<Object?>>());
                expect((page['items']! as List).length, lessThanOrEqualTo(50));
              }
            }
            expect(capture.samples, hasLength(_runs));
            final first = capture.samples.first;
            final plan = await writer.execute(
              'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ${first.sql}',
              parameters: first.arguments,
            );
            final elapsedMs = capture.samples.map((s) => s.elapsedMs).toList()
              ..sort();
            final p95 = elapsedMs[(_runs * .95).ceil() - 1];
            final report = {
              'dataset': label,
              'surface': surface ?? 'history',
              'populationReceipts': population.single.single,
              'viewerRole': entry.key,
              'viewer': viewer,
              'viewerReceipts': entry.value[1],
              'runs': _runs,
              'configuredStatementTimeoutMs': env.pgStatementTimeoutMs,
              'effectiveStatementDeadlineMs': deadlineMs,
              'sqlElapsedMs': elapsedMs,
              'p95Ms': p95,
              'explainAnalyzeBuffers': plan.single.single,
            };
            final reportFile = File(
              'build/perf/attention_feed/$source${dataset.largeHistory ? '-large-history' : ''}-${entry.key}-${surface ?? 'history'}.json',
            );
            await reportFile.parent.create(recursive: true);
            await reportFile.writeAsString(jsonEncode(report));
            print(
              jsonEncode({
                ...report..remove('explainAnalyzeBuffers'),
                'explainReport': reportFile.path,
              }),
            );
            expect(
              p95,
              lessThan(deadlineMs * .5),
              reason:
                  '$source ${entry.key}: AttentionFeed SQL needs at least 50% '
                  'headroom under its effective statement deadline. Inspect '
                  'the emitted EXPLAIN before choosing a query or index fix.',
            );
          }
        },
      );
    }
  }
}

/// The existing live-obligations budget fixture uses 128 Requests and 16
/// receipts per Request. Retain its Request count and exercise longer history
/// here: 128 receipts each, plus a separate viewer with 32 total receipts.
/// Only the disposable perfsynth clone is seeded.
Future<void> _seedLargeReceiptHistory(pg.Connection writer) async {
  for (final (slot, viewer) in [_historyHeavy, _historyTypical].indexed) {
    await writer.execute(
      pg.Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@viewer, @viewer, @key)
'''),
      parameters: {
        'viewer': viewer,
        'key': pgTestPublicKey('feedhistory', slot + 1),
      },
    );
    final beaconCount = viewer == _historyHeavy ? _historyBeacons : 1;
    final receiptCount = viewer == _historyHeavy
        ? _historyBeacons * _historyReceiptsPerBeacon
        : 32;
    await writer.execute(
      pg.Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
SELECT 'Bfeedhistory' || @viewer || n, @viewer,
       'History request', 'Attention history performance fixture', 0
FROM generate_series(0, @beacons::int - 1) n
'''),
      parameters: {'viewer': viewer, 'beacons': beaconCount},
    );
    await writer.execute(
      pg.Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority, title, body, action_url,
  dedup_key, beacon_id, source_event_key, destination_kind,
  presentation_key, presentation_payload, suppression_class, access_policy,
  created_at
)
SELECT 'Nfeedhistory' || @viewer || n, @viewer,
       'coordination', 'coordinationChanged', 'normal',
       'Status changed', 'History fixture', '/attention',
       'feedhistory-dedup-' || @viewer || n,
       'Bfeedhistory' || @viewer || (n % @beacons::int),
       'feedhistory-source-' || @viewer || n, 'beacon',
       'request_status_changed', '{"eventType":"fixture"}'::jsonb,
       'standard', 'beacon_content',
       '2026-10-30T00:00:00Z'::timestamptz + n * interval '1 second'
FROM generate_series(0, @receipts::int - 1) n
'''),
      parameters: {
        'viewer': viewer,
        'beacons': beaconCount,
        'receipts': receiptCount,
      },
    );
  }
  await writer.execute('ANALYZE public.notification_outbox');
  await writer.execute('ANALYZE public.beacon');
}

final class _FeedStatement {
  _FeedStatement(this.sql, this.arguments, this.elapsedMs);

  final String sql;
  final List<Object?> arguments;
  final double elapsedMs;
}

final class _FeedStatements extends QueryInterceptor {
  final samples = <_FeedStatement>[];

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    if (!statement.contains('summary AS (') ||
        !statement.contains('visible_attention_receipts')) {
      return executor.runSelect(statement, args);
    }
    final clock = Stopwatch()..start();
    try {
      return await executor.runSelect(statement, args);
    } finally {
      samples.add(
        _FeedStatement(
          statement,
          List.of(args),
          clock.elapsedMicroseconds / 1000,
        ),
      );
    }
  }
}
