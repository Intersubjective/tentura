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
import 'attention_feed_pre_fix_sql.dart';
import 'attention_feed_statement_rows.dart';

const _runs = 20;
const _historyBeacons = 128;
const _historyReceiptsPerBeacon = 128;
const _historyHeavy = 'Ufeedscaleheavy';
const _historyTypical = 'Ufeedscaletypical';
const _warmups = 3;
const _wideHistoryViewer = 'Ufeedwideviewer';
const _wideHistoryRequests = 6000;
const _wideHistoryAuthors = 32;
const _wideHistoryReceiptsPerRequest = 2;

/// Opt-in: name a local database restored from a production-like dump to
/// compare the current feed statement with the frozen pre-fix one on it.
const _preFixDatasetEnv = 'TENTURA_ATTENTION_FEED_PRE_FIX_DATASET';

/// Opt-in, with [_preFixDatasetEnv]: the speed-up over the pre-fix p95 that
/// the comparison must show (for example `3`). Unset, it only reports.
const _preFixMinSpeedupEnv = 'TENTURA_ATTENTION_FEED_PRE_FIX_MIN_SPEEDUP';
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
  final wideTarget = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ATTENTION_FEED_WIDE_HISTORY_TEST_DB',
    defaultNamePrefix: 'tentura_test_feed_wide',
  );
  test(
    'for a viewer whose history spans $_wideHistoryRequests Requests '
    'forwarded by $_wideHistoryAuthors people, the history feed returns the '
    "pre-fix rows in at most a third of the pre-fix statement's p95 time",
    skip: await pgSkipReason(wideTarget),
    () => _expectWideForwardedHistoryFasterThanPreFix(wideTarget),
  );

  final preFixDataset = Platform.environment[_preFixDatasetEnv] ?? '';
  const preFixSkipReason =
      'Local measurement only: set $_preFixDatasetEnv to a local database '
      'restored from a dev dump (run with TENTURA_TEST_PG=shared when it lives '
      'in the persistent postgres container).';
  for (final surface in <String?>[null, 'activity']) {
    test(
      'on a restored production-like dataset the AttentionFeed statement '
      'returns the pre-fix rows for the three heaviest and a typical viewer '
      "in at most a third of the pre-fix statement's p95 time for the "
      'heaviest, surface ${surface ?? 'history'}',
      skip: preFixDataset.isEmpty ? preFixSkipReason : false,
      () async {
        if (preFixDataset.isEmpty) {
          // Reached only under --run-skipped.
          markTestSkipped(preFixSkipReason);
          return;
        }
        await _compareFeedStatementWithPreFixOnDataset(preFixDataset, surface);
      },
    );
  }
}

/// A history wide in *Requests*, not in receipts per Request: every Request
/// is someone else's, so each one costs the viewer a full visibility decision.
/// Three in four were forwarded to the viewer (readable); the fourth was not
/// (unreadable, filtered out). The page is still 50 rows, so the feed must not
/// pay a per-Request visibility price for the whole history on every read.
///
/// Seeded on the pre-fix schema, measured against the frozen pre-fix SQL and
/// then against head in the same test — a speed-up, not an absolute budget,
/// so the guard does not depend on how fast the machine is.
Future<void> _expectWideForwardedHistoryFasterThanPreFix(
  DisposablePgTarget target,
) async {
  final session = await setUpDisposablePgWriter(
    target: target,
    createPgmer2Extension: true,
    lastInclusiveVersion: preFixSchemaVersion,
  );
  final databases = <TenturaDb>[];
  addTearDown(() async {
    for (final database in databases) {
      await database.close();
    }
    await tearDownDisposablePgWriter(session: session);
  });
  final writer = session.writer;
  await _seedWideForwardedHistory(writer);
  final expectedRows = await writer.execute(
    pg.Sql.named('''
SELECT receipt.id
FROM public.notification_outbox receipt
JOIN public.beacon_forward_edge fe
  ON fe.beacon_id = receipt.beacon_id
 AND fe.recipient_id = receipt.account_id
 AND fe.cancelled_at IS NULL
WHERE receipt.account_id = @viewer
ORDER BY receipt.created_at DESC, receipt.id DESC
LIMIT 51
'''),
    parameters: {'viewer': _wideHistoryViewer},
  );
  final comparison = await _compareWithPreFix(
    writer: writer,
    env: target.databaseEnv,
    openDatabase: (capture) {
      final database = TenturaDb(
        target.databaseEnv,
        scopeInterceptor: () => capture,
      );
      databases.add(database);
      return database;
    },
    viewers: {
      'heaviest': (
        viewer: _wideHistoryViewer,
        outboxRows: _wideHistoryRequests * _wideHistoryReceiptsPerRequest,
        visibleReceipts:
            _wideHistoryRequests ~/ 4 * 3 * _wideHistoryReceiptsPerRequest,
      ),
    },
    surface: null,
    checkReference: (reference) => expect(
      [
        for (final row in reference[_wideHistoryViewer]!)
          if (row['id'] != null) row['id'],
      ],
      orderedEquals(expectedRows.map((row) => row[0])),
      reason:
          'The pre-fix page is the 51 newest receipts on forwarded '
          'Requests; otherwise the fixture measures the wrong thing.',
    ),
  );
  await comparison.writeReport('seeded-wide-forwarded-history-vs-pre-fix', {
    'dataset': 'seeded wide forwarded history',
    'requests': _wideHistoryRequests,
    'authors': _wideHistoryAuthors,
    'receiptsPerRequest': _wideHistoryReceiptsPerRequest,
  });
  comparison.expectSpeedup(
    3,
    label: 'seeded wide history ($_wideHistoryRequests forwarded Requests)',
  );
}

/// Seeds [_wideHistoryViewer] and the Requests of [_wideHistoryAuthors]
/// other people, each Request with [_wideHistoryReceiptsPerRequest] receipts
/// for the viewer, newest last. Forwards go through the real trigger path.
Future<void> _seedWideForwardedHistory(pg.Connection writer) async {
  await writer.execute(
    pg.Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@viewer, @viewer, @viewer || '-key')
'''),
    parameters: {'viewer': _wideHistoryViewer},
  );
  await writer.execute(
    pg.Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
SELECT 'Ufeedwideauthor' || a, 'Author ' || a, 'Ufeedwideauthor' || a || '-key'
FROM generate_series(0, @authors::int - 1) a
'''),
    parameters: {'authors': _wideHistoryAuthors},
  );
  await writer.execute(
    pg.Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
SELECT 'Bfeedwide' || i, 'Ufeedwideauthor' || (i % @authors::int),
       'Wide history request', 'Attention feed wide history fixture', 0
FROM generate_series(0, @requests::int - 1) i
'''),
    parameters: {
      'authors': _wideHistoryAuthors,
      'requests': _wideHistoryRequests,
    },
  );
  await writer.execute(
    pg.Sql.named('''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, note, created_at
)
SELECT 'FEfeedwide' || i, 'Bfeedwide' || i,
       'Ufeedwideauthor' || (i % @authors::int), @viewer, 'fixture', now()
FROM generate_series(0, @requests::int - 1) i
WHERE i % 4 <> 3
'''),
    parameters: {
      'viewer': _wideHistoryViewer,
      'authors': _wideHistoryAuthors,
      'requests': _wideHistoryRequests,
    },
  );
  await writer.execute(
    pg.Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority, title, body, action_url,
  dedup_key, beacon_id, source_event_key, destination_kind,
  presentation_key, presentation_payload, suppression_class, access_policy,
  created_at
)
SELECT 'Nfeedwide' || i || '_' || r, @viewer,
       'coordination', 'coordinationChanged', 'normal',
       'Status changed', 'Wide history fixture', '/attention',
       'feedwide-dedup-' || i || '_' || r, 'Bfeedwide' || i,
       'feedwide-source-' || i || '_' || r, 'beacon',
       'request_status_changed', '{"eventType":"fixture"}'::jsonb,
       'standard', 'beacon_content',
       '2026-10-30T00:00:00Z'::timestamptz
         + (i * @perRequest::int + r) * interval '1 second'
FROM generate_series(0, @requests::int - 1) i,
     generate_series(0, @perRequest::int - 1) r
'''),
    parameters: {
      'viewer': _wideHistoryViewer,
      'requests': _wideHistoryRequests,
      'perRequest': _wideHistoryReceiptsPerRequest,
    },
  );
  await writer.execute('ANALYZE');
}

/// Local measurement on a database restored from a dev dump, cloned and
/// compared exactly like the seeded guard. Viewers: the three with the most
/// visible attention receipts (ties broken by outbox rows) and the median
/// viewer with any visible receipt. The heaviest must get the speed-up named
/// by [_preFixMinSpeedupEnv] (default 3; `0` only reports).
Future<void> _compareFeedStatementWithPreFixOnDataset(
  String dataset,
  String? surface,
) async {
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
    final exists = await admin.execute(
      pg.Sql.named('SELECT 1 FROM pg_database WHERE datname = @name'),
      parameters: {'name': dataset},
    );
    if (exists.isEmpty) {
      fail(
        '$_preFixDatasetEnv names "$dataset", which does not exist on '
        '${target.adminEnv.pgHost}:${target.adminEnv.pgPort}. Restore the '
        'dump there, and run with TENTURA_TEST_PG=shared if it lives in the '
        'persistent postgres container.',
      );
    }
    await withDisposablePgLifecycleLock(target.adminEnv, () async {
      await admin.execute(
        'CREATE DATABASE "${target.databaseName}" TEMPLATE "$dataset"',
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
  await migrateDbSchemaThrough(writer, preFixSchemaVersion);
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

  // Ranked on the pre-fix schema, by what each viewer can actually see.
  final ranked = await writer.execute('''
SELECT outbox.account_id, outbox.rows, visible.receipts
FROM (
  SELECT account_id, count(*)::int AS rows
  FROM public.notification_outbox
  GROUP BY account_id
) outbox
CROSS JOIN LATERAL (
  SELECT count(*)::int AS receipts
  FROM public.visible_attention_receipts(outbox.account_id)
) visible
WHERE visible.receipts > 0
ORDER BY visible.receipts DESC, outbox.rows DESC, outbox.account_id
''');
  expect(ranked.length, greaterThan(4), reason: '$dataset has receipts.');
  _ViewerStats stats(pg.ResultRow row) => (
    viewer: row[0]! as String,
    outboxRows: row[1]! as int,
    visibleReceipts: row[2]! as int,
  );
  final viewers = {
    for (final (rank, row) in ranked.take(3).indexed)
      rank == 0 ? 'heaviest' : 'heavy #${rank + 1}': stats(row),
    'typical': stats(ranked[ranked.length ~/ 2]),
  };

  final pools = <MainDbPool>[];
  final databases = <TenturaDb>[];
  addTearDown(() async {
    for (final database in databases) {
      await database.close();
    }
    for (final pool in pools) {
      await pool.close();
    }
  });
  final comparison = await _compareWithPreFix(
    writer: writer,
    env: env,
    openDatabase: (capture) {
      final pool = MainDbPool(env);
      pools.add(pool);
      final database = TenturaDb.scoped(pool, scopeInterceptor: () => capture);
      databases.add(database);
      return database;
    },
    viewers: viewers,
    surface: surface,
  );
  await comparison.writeReport(
    '$dataset-vs-pre-fix-${surface ?? 'history'}',
    {'dataset': dataset},
  );
  final minSpeedup =
      double.tryParse(Platform.environment[_preFixMinSpeedupEnv] ?? '') ?? 3;
  if (minSpeedup > 0) {
    comparison.expectSpeedup(
      minSpeedup,
      label: '$dataset, surface ${surface ?? 'history'}',
    );
  }
}

typedef _ViewerStats = ({String viewer, int outboxRows, int visibleReceipts});

/// Pre-fix vs head on one database, which must be at [preFixSchemaVersion].
///
/// 1. Pre-fix schema: the frozen pre-fix feed statement's rows for every
///    viewer (the reference), then its timing for the heaviest viewer.
/// 2. Migrate to head. Every viewer reads the feed through the real GraphQL
///    resolver; the statement it issues must return the reference rows in the
///    reference order. The heaviest viewer's statement is then timed.
///
/// Both timings use one channel: `customSelect` on a fresh request-scoped
/// database, the interceptor timing only the statement's execution, after
/// [_warmups] unmeasured runs.
Future<_PreFixComparison> _compareWithPreFix({
  required pg.Connection writer,
  required Env env,
  required TenturaDb Function(StatementRowCapture capture) openDatabase,
  required Map<String, _ViewerStats> viewers,
  required String? surface,
  void Function(Map<String, List<Map<String, Object?>>> reference)?
  checkReference,
}) async {
  final heavy = viewers['heaviest']!.viewer;
  final frozenSql = surface == null
      ? preFixAttentionFeedHistorySql
      : preFixAttentionFeedActivitySql;
  List<Object?> frozenArguments(String viewer) => [
    viewer,
    'all',
    null,
    surface,
    51,
  ];
  await writer.execute('ANALYZE');

  final before = StatementRowCapture();
  final beforeDatabase = openDatabase(before);
  final reference = <String, List<Map<String, Object?>>>{};
  for (final stats in viewers.values) {
    before.clear();
    await _select(beforeDatabase, frozenSql, frozenArguments(stats.viewer));
    reference[stats.viewer] = before.feedStatementRows();
  }
  expect(
    reference[heavy]!.where((row) => row['id'] != null),
    isNotEmpty,
    reason: 'The heaviest viewer must have a visible feed.',
  );
  checkReference?.call(reference);
  final beforeMs = await _timeStatement(
    beforeDatabase,
    before,
    frozenSql,
    frozenArguments(heavy),
  );
  final beforePlan = await writer.execute(
    'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) $frozenSql',
    parameters: frozenArguments(heavy),
  );

  await migrateDbSchema(writer);
  await writer.execute('ANALYZE');

  final after = StatementRowCapture();
  final afterDatabase = openDatabase(after);
  final controller = GraphqlController(
    env,
    schema: TenturaGraphQL(
      GraphQLSchema(
        queryType: GraphQLObjectType('Query', 'Query root')
          ..fields.add(
            QueryAttention(
              query: AttentionRepository(afterDatabase),
            ).attentionFeed,
          ),
      ),
    ),
  );
  CapturedStatement? heavyStatement;
  for (final MapEntry(key: role, value: stats) in viewers.entries) {
    final handler = requestContextIoAdapter((request) {
      return controller.handler(
        request.change(context: {kContextJwtKey: JwtEntity(sub: stats.viewer)}),
      );
    });
    after.clear();
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
    expectSameFeedRows(
      actual: after.feedStatementRows(),
      expected: reference[stats.viewer]!,
      reason:
          '$role viewer ${stats.viewer}, surface ${surface ?? 'history'}: the '
          'feed statement must return the pre-fix rows in the pre-fix order.',
    );
    if (stats.viewer == heavy) heavyStatement = after.feedStatements.single;
  }
  final afterMs = await _timeStatement(
    afterDatabase,
    after,
    heavyStatement!.sql,
    heavyStatement.arguments,
  );
  final afterPlan = await writer.execute(
    'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ${heavyStatement.sql}',
    parameters: heavyStatement.arguments,
  );
  return _PreFixComparison(
    surface: surface,
    viewers: viewers,
    beforeMs: beforeMs,
    afterMs: afterMs,
    beforePlan: beforePlan.single.single,
    afterPlan: afterPlan.single.single,
  );
}

Future<void> _select(TenturaDb database, String sql, List<Object?> arguments) =>
    database
        .customSelect(sql, variables: [for (final a in arguments) Variable(a)])
        .get();

/// [_warmups] unmeasured runs, then [_runs] timed ones; sorted milliseconds.
Future<List<double>> _timeStatement(
  TenturaDb database,
  StatementRowCapture capture,
  String sql,
  List<Object?> arguments,
) async {
  for (var run = 0; run < _warmups; run++) {
    await _select(database, sql, arguments);
  }
  capture.clear();
  for (var run = 0; run < _runs; run++) {
    await _select(database, sql, arguments);
  }
  final elapsed = [for (final s in capture.feedStatements) s.elapsedMs]..sort();
  expect(
    elapsed,
    hasLength(_runs),
    reason: 'Every measured run must be the feed statement.',
  );
  return elapsed;
}

final class _PreFixComparison {
  _PreFixComparison({
    required this.surface,
    required this.viewers,
    required this.beforeMs,
    required this.afterMs,
    required this.beforePlan,
    required this.afterPlan,
  });

  final String? surface;
  final Map<String, _ViewerStats> viewers;
  final List<double> beforeMs;
  final List<double> afterMs;
  final Object? beforePlan;
  final Object? afterPlan;

  double _p50(List<double> sorted) => sorted[_runs ~/ 2];
  double _p95(List<double> sorted) => sorted[(_runs * .95).ceil() - 1];

  Future<void> writeReport(String name, Map<String, Object?> extra) async {
    final report = {
      ...extra,
      'surface': surface ?? 'history',
      'viewers': {
        for (final MapEntry(key: role, value: stats) in viewers.entries)
          role: {
            'viewer': stats.viewer,
            'outboxRows': stats.outboxRows,
            'visibleReceipts': stats.visibleReceipts,
          },
      },
      'runs': _runs,
      'warmups': _warmups,
      'beforeSqlElapsedMs': beforeMs,
      'beforeP50Ms': _p50(beforeMs),
      'beforeP95Ms': _p95(beforeMs),
      'afterSqlElapsedMs': afterMs,
      'afterP50Ms': _p50(afterMs),
      'afterP95Ms': _p95(afterMs),
      'beforeExplainAnalyzeBuffers': beforePlan,
      'afterExplainAnalyzeBuffers': afterPlan,
    };
    final reportFile = File('build/perf/attention_feed/$name.json');
    await reportFile.parent.create(recursive: true);
    await reportFile.writeAsString(jsonEncode(report));
    print(
      jsonEncode({
        ...report
          ..remove('beforeExplainAnalyzeBuffers')
          ..remove('afterExplainAnalyzeBuffers'),
        'explainReport': reportFile.path,
      }),
    );
  }

  void expectSpeedup(double factor, {required String label}) {
    final before = _p95(beforeMs);
    final after = _p95(afterMs);
    expect(
      after,
      lessThanOrEqualTo(before / factor),
      reason:
          '$label, heaviest viewer ${viewers['heaviest']!.viewer}: the '
          'AttentionFeed statement p95 (${after.toStringAsFixed(1)} ms) must '
          'be at most 1/$factor of the pre-fix p95 '
          '(${before.toStringAsFixed(1)} ms) measured in the same run. Inspect '
          'the emitted EXPLAIN pair for the dominating node.',
    );
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
