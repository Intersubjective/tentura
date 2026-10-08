// `perf` suites are timing-sensitive, so like `mr` suites they run serialised
// (`-j 1`) and outside the default and plain-`pg` runs.
@Tags(['perf', 'pg', 'mr'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/mappers/constellation_gql_maps.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/constellation_field_repository.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/gql_public/mutual_score_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';
import 'package:tentura_server/domain/use_case/constellation_field_case.dart';
import 'package:tentura_server/env.dart';

import '../support/disposable_pg_target.dart';
import 'perf_fixtures.dart';
import 'perf_recorder.dart';

/// Discoverable Request candidates (#233): the work the FULL read's
/// discoverable query does on a 99-peer sparse field with C candidates of
/// which a given share is readable, plus whole-FULL latency.
///
/// The suite measures whatever code and schema it runs against, so the same
/// file yields the baseline (author-only `m0193` index, readability applied
/// before LIMIT) and the current (partial `(user_id, id)` index, keyset scan)
/// reports. The discoverable statements a FULL read really issues are
/// captured and replayed under `EXPLAIN (ANALYZE, BUFFERS)` with function
/// tracking, so rows examined and readability verdicts are measured rather
/// than derived. Reports land in `build/perf/discoverable/<mode>/`.
///
/// `TENTURA_DISCOVERABLE_PERF_COPY_DB` + `TENTURA_DISCOVERABLE_PERF_VIEWER`
/// measure an existing dataset instead (default and show-closed filters for
/// that viewer). Point them at a disposable *copy* of the dataset, with its
/// graph loaded into MeritRank (`meritrank_init()`): a FULL read may write the
/// viewer's cursor row.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_DISCOVERABLE_PERF_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_perf_discoverable',
  );
  final skipReason = await canReachPostgresAdmin(target)
      ? null
      : 'Postgres admin database not reachable for discoverable perf suite';

  const warmups = 3;
  const measuredAttempts = 30;
  const fixtureSpec = PerfFixture.sparseTrust(visibleUsers: 100);
  final copyDb = Platform.environment['TENTURA_DISCOVERABLE_PERF_COPY_DB'];
  final copyViewer = Platform.environment['TENTURA_DISCOVERABLE_PERF_VIEWER'];
  if (copyDb != null) {
    if (const {'postgres', 'tentura_perfsynth', 'tentura_devcopy'}
            .contains(copyDb) ||
        copyViewer == null) {
      throw ArgumentError(
        'TENTURA_DISCOVERABLE_PERF_COPY_DB must name a disposable copy, and '
        'TENTURA_DISCOVERABLE_PERF_VIEWER the viewer to measure',
      );
    }
  }
  final fixtures = copyDb == null
      ? const [
          _Fixture(candidates: 1000, readableEvery: 1, showClosed: false),
          _Fixture(candidates: 10000, readableEvery: 1, showClosed: false),
          _Fixture(candidates: 10000, readableEvery: 10, showClosed: true),
          _Fixture(candidates: 10000, readableEvery: 100, showClosed: true),
        ]
      : [
          for (final showClosed in [false, true])
            _Fixture.dataset(
              Platform.environment['TENTURA_DISCOVERABLE_PERF_LABEL'] ??
                  copyDb,
              showClosed: showClosed,
            ),
        ];

  group('discoverable candidates', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late PerfDbMeter meter;
    late _StatementCapture capture;
    late TenturaDb db;
    late PerfFixtureSeed seed;
    late ConstellationFieldCase fieldCase;
    late String mode;
    final reports = <String, Map<String, Object?>>{};

    setUpAll(() async {
      if (skipReason != null) return;
      final databaseEnv = copyDb == null
          ? target.databaseEnv
          : Env(
              environment: Environment.test,
              pgHost: target.databaseEnv.pgHost,
              pgPort: target.databaseEnv.pgPort,
              pgDatabase: copyDb,
              pgUsername: target.databaseEnv.pgUsername,
              pgPassword: target.databaseEnv.pgPassword,
              printEnv: false,
              isDebugModeOn: false,
            );
      if (copyDb == null) {
        session = await setUpDisposablePgWriter(
          target: target,
          createPgmer2Extension: true,
        );
        writer = session.writer;
        seed = await fixtureSpec.seed(writer);
      } else {
        writer = await Connection.open(
          databaseEnv.pgEndpoint,
          settings: databaseEnv.pgEndpointSettings,
        );
        seed = PerfFixtureSeed(viewerId: copyViewer!, peerIds: const []);
      }
      meter = PerfDbMeter();
      capture = _StatementCapture();
      db = TenturaDb.forTest(
        database: PgDatabase.opened(
          meter.instrument(
            Pool<dynamic>.withEndpoints(
              [databaseEnv.pgEndpoint],
              settings: databaseEnv.pgPoolSettings,
            ),
          ),
          enableMigrations: false,
        ).interceptWith(meter).interceptWith(capture),
      );
      await requireNonEmptyMeritRankGraph(writer);
      fieldCase = ConstellationFieldCase(
        ConstellationFieldRepository(db, _EmptyProfileLookup()),
        env: Env(environment: Environment.test),
        logger: Logger('DiscoverableCandidatesPerf'),
      );
      final indexed = await writer.execute(
        "SELECT 1 FROM pg_indexes WHERE schemaname = 'public' "
        "AND indexname = 'beacon_discoverable_user_id_id_idx'",
      );
      mode = indexed.isEmpty ? 'baseline' : 'current';
      // Isolates the index from the keyset scan: current code, no index.
      if (copyDb == null &&
          Platform.environment['TENTURA_DISCOVERABLE_PERF_DROP_INDEX'] == '1' &&
          indexed.isNotEmpty) {
        await writer.execute(
          'DROP INDEX public.beacon_discoverable_user_id_id_idx',
        );
        mode = 'current_without_index';
      }
      final schema = await writer.execute(
        'SELECT max(version) FROM schema_version',
      );
      final authorIndex = await writer.execute(
        "SELECT indexdef FROM pg_indexes WHERE schemaname = 'public' "
        "AND indexname = 'beacon_discoverable_author_idx'",
      );

      for (final fixture in fixtures) {
        if (!fixture.isDataset) {
          await _seedCandidates(writer, seed, fixture);
        }
        final population = await _population(writer, seed, fixture);
        final params = (
          filters: ConstellationFieldMembershipFilters(
            showClosed: fixture.showClosed,
          ),
          projection: ConstellationProjection.full,
        );
        Future<String> encodedFull() async => jsonEncode(
          constellationFieldToGqlMap(
            await fieldCase.readSnapshot(
              viewerId: seed.viewerId,
              context: '',
              params: params,
            ),
          ),
        );

        for (var i = 0; i < warmups; i++) {
          await encodedFull();
        }
        final recorder = PerfRecorder(
          fixture: fixture.name,
          parameters: {
            ...fixture.parameters,
            'candidates': population.candidates,
            'readablePercent': population.readablePercent,
          },
          db: db,
          meter: meter,
          probeConnection: writer,
        );
        for (var i = 0; i < measuredAttempts; i++) {
          await recorder.attempt((scope) => scope.execution(encodedFull));
        }

        capture.start();
        final payload =
            jsonDecode(await encodedFull()) as Map<String, Object?>;
        final statements = capture.stop();
        final work = await _replay(writer, statements);

        recorder.report.extras.addAll({
          'mode': mode,
          'schemaVersion': schema.single.single,
          if (authorIndex.isNotEmpty)
            'baselineAuthorIndexDefinition': authorIndex.single.single,
          'measuredCandidates': population.candidates,
          'measuredReadablePercent': population.readablePercent,
          'returnedRequests': (payload['requests']! as List).length,
          ...work,
        });
        final file = await recorder.writeReport(
          Directory('build/perf/discoverable/$mode'),
        );
        reports[fixture.name] =
            jsonDecode(await file.readAsString()) as Map<String, Object?>;
      }
    });

    tearDownAll(() async {
      if (skipReason != null) return;
      await db.close();
      if (copyDb == null) {
        await tearDownDisposablePgWriter(session: session);
      } else {
        await writer.close();
      }
    });

    test('measures every fixture against its real candidate population', () {
      for (final fixture in fixtures) {
        final report = reports[fixture.name]!;
        if (!fixture.isDataset) {
          expect(report['measuredCandidates'], fixture.candidates);
          expect(
            report['measuredReadablePercent'],
            closeTo(100 / fixture.readableEvery!, 0.01),
          );
        }
        // The field shows up to the Request cap, whichever query found them.
        expect(report['returnedRequests'], greaterThan(0));
        expect(report['rowsExamined'], greaterThan(0));
        expect(report['readabilityCalls'], greaterThan(0));
        expect(report['candidateStatements'], greaterThan(0));
      }
    }, skip: skipReason);
  });
}

final class _Fixture {
  const _Fixture({
    required int this.candidates,
    required int this.readableEvery,
    required this.showClosed,
  }) : dataset = null;

  /// The viewer's own candidates in an existing dataset.
  const _Fixture.dataset(String this.dataset, {required this.showClosed})
    : candidates = null,
      readableEvery = null;

  final String? dataset;
  final int? candidates;

  bool get isDataset => dataset != null;

  /// Every n-th candidate is open (status 0) and so readable through
  /// discovery; the others are closed (status 5), which only the show-closed
  /// filter lists and which discovery does not make readable.
  final int? readableEvery;
  final bool showClosed;

  String get name => isDataset
      ? '${dataset}_${showClosed ? 'show_closed' : 'default'}'
      : 'discoverable_c${candidates}_r${(100 / readableEvery!).round()}';

  Map<String, Object?> get parameters => {
    'showClosed': showClosed,
    if (isDataset) 'dataset': dataset,
  };
}

Future<void> _seedCandidates(
  Connection writer,
  PerfFixtureSeed seed,
  _Fixture fixture,
) async {
  await writer.execute("DELETE FROM public.beacon WHERE id LIKE 'Bdc%'");
  final every = fixture.readableEvery!;
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, kind, status, published_at, is_discoverable)
SELECT 'Bdc' || lpad(n::text, 9, '0'),
       (@peers::text[])[n % cardinality(@peers::text[]) + 1],
       'perf ' || n, '', 0,
       CASE WHEN n % @every::int = 0 THEN 0 ELSE 5 END,
       now(), true
FROM generate_series(1, @candidates::int) n
'''),
    parameters: {
      'peers': TypedValue(Type.textArray, seed.peerIds),
      'every': every,
      'candidates': fixture.candidates,
    },
  );
  await writer.execute('ANALYZE public.beacon');
}

/// The candidate population as the field defines it, and the measured share
/// of it the viewer may read.
Future<({int candidates, double readablePercent})> _population(
  Connection writer,
  PerfFixtureSeed seed,
  _Fixture fixture,
) async {
  final rows = await writer.execute(
    Sql.named('''
WITH peers AS (
  SELECT public.person_visible_peer_ids_tx(@viewer, '') AS ids
),
cand AS (
  SELECT b.id FROM public.beacon b
  WHERE b.user_id = ANY((SELECT ids FROM peers)::text[]) AND b.user_id <> @viewer
    AND b.kind = 0 AND b.is_discoverable
    AND b.published_at IS NOT NULL AND b.status = ANY(@statuses::int[])
)
SELECT (SELECT count(*)::int FROM cand),
       (SELECT count(*)::int FROM public.beacon_readable_ids(
          @viewer, (SELECT array_agg(id) FROM cand)))
'''),
    parameters: {
      'statuses': TypedValue(
        Type.integerArray,
        constellationFieldBeaconStatuses(
          showClosed: fixture.showClosed,
        ).toList(),
      ),
      'viewer': seed.viewerId,
    },
  );
  final candidates = rows.single[0]! as int;
  final readable = rows.single[1]! as int;
  return (
    candidates: candidates,
    readablePercent: candidates == 0 ? 0.0 : readable * 100 / candidates,
  );
}

const _functionCallsSql =
    'SELECT coalesce(pg_stat_get_xact_function_calls(@function::regprocedure), '
    '0)::int';

typedef _Statement = ({String sql, List<Object?> args});

/// Collects the discoverable statements one FULL read issues.
final class _StatementCapture extends QueryInterceptor {
  List<_Statement>? _statements;

  void start() => _statements = [];

  List<_Statement> stop() {
    final statements = _statements!;
    _statements = null;
    return statements;
  }

  static bool isCandidateScan(String sql) =>
      sql.contains('FROM public.beacon b') &&
      sql.contains('b.is_discoverable') &&
      sql.contains(r'b.user_id = ANY($2::text[])');

  static bool isReadabilityBatch(String sql) =>
      sql.contains('public.beacon_readable_ids(');

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (_statements != null &&
        (isCandidateScan(statement) || isReadabilityBatch(statement))) {
      _statements!.add((sql: statement, args: List.of(args)));
    }
    return super.runSelect(executor, statement, args);
  }
}

TypedValue _typed(Object? value) => switch (value) {
  final TypedValue typed => typed,
  null => TypedValue(Type.unspecified, null),
  final int v => TypedValue(Type.bigInteger, v),
  final String v => TypedValue(Type.text, v),
  final bool v => TypedValue(Type.boolean, v),
  final double v => TypedValue(Type.double, v),
  _ => throw ArgumentError.value(value, 'value', 'Unsupported type'),
};

/// Replays [statements] in one rolled-back transaction under
/// `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)`, with PL/SQL function calls
/// tracked, and sums the work they did.
///
/// * rows examined: beacon rows the candidate scans read (returned plus
///   removed by filter or recheck);
/// * readability verdicts: `beacon_can_read_content` calls (per-row checks)
///   plus the ids handed to set-wise `beacon_readable_ids` batches.
Future<Map<String, Object?>> _replay(
  Connection writer,
  List<_Statement> statements,
) async {
  final plans = <Map<String, Object?>>[];
  var rowsExamined = 0;
  var perRowChecks = 0;
  var batchedVerdicts = 0;
  var batchCalls = 0;
  var candidateStatements = 0;
  await writer.execute('BEGIN');
  try {
    await writer.execute("SET LOCAL track_functions = 'all'");
    Future<int> calls(String function) async {
      final rows = await writer.execute(
        Sql.named(_functionCallsSql),
        parameters: {'function': function},
      );
      return rows.single.single! as int;
    }

    const perRow = 'public.beacon_can_read_content(text,text)';
    const batch = 'public.beacon_readable_ids(text,text[])';
    for (final (index, statement) in statements.indexed) {
      final candidateScan = _StatementCapture.isCandidateScan(statement.sql);
      final perRowBefore = await calls(perRow);
      final batchBefore = await calls(batch);
      final result = await writer.execute(
        'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ${statement.sql}',
        parameters: [for (final arg in statement.args) _typed(arg)],
      );
      final plan = _decodePlan(result.single.single);
      perRowChecks += await calls(perRow) - perRowBefore;
      final batchDelta = await calls(batch) - batchBefore;
      batchCalls += batchDelta;
      if (_StatementCapture.isReadabilityBatch(statement.sql)) {
        // `$2` is the batch of candidate ids asked about.
        final ids = statement.args[1];
        final length = ids is TypedValue
            ? (ids.value! as List).length
            : (ids! as List).length;
        batchedVerdicts += batchDelta == 0 ? 0 : length;
      }
      if (candidateScan) {
        candidateStatements++;
        rowsExamined += _beaconRowsRead(plan);
      }
      plans.add({
        'label': candidateScan
            ? 'candidate_scan_$index'
            : 'readability_batch_$index',
        'plan': plan,
      });
    }
  } finally {
    await writer.execute('ROLLBACK');
  }
  return {
    'candidateStatements': candidateStatements,
    'rowsExamined': rowsExamined,
    'readabilityCalls': perRowChecks + batchedVerdicts,
    'perRowReadabilityCalls': perRowChecks,
    'batchedReadabilityVerdicts': batchedVerdicts,
    'readabilityBatchCalls': batchCalls,
    'explain': plans,
  };
}

List<Object?> _decodePlan(Object? value) =>
    (value is String ? jsonDecode(value) : value)! as List<Object?>;

Iterable<Map<String, Object?>> _nodes(Object? value) sync* {
  if (value is Map<String, Object?>) {
    yield value;
    for (final child in value.values) {
      yield* _nodes(child);
    }
  } else if (value is List) {
    for (final child in value) {
      yield* _nodes(child);
    }
  }
}

int _beaconRowsRead(List<Object?> plan) {
  var total = 0;
  for (final node in _nodes(plan)) {
    if (node['Relation Name'] != 'beacon') continue;
    final loops = (node['Actual Loops'] as num?) ?? 1;
    final rows =
        ((node['Actual Rows'] as num?) ?? 0) +
        ((node['Rows Removed by Filter'] as num?) ?? 0) +
        ((node['Rows Removed by Index Recheck'] as num?) ?? 0);
    total += (rows * loops).round();
  }
  return total;
}

final class _EmptyProfileLookup implements UserProfileBatchLookup {
  @override
  Future<Map<String, UserEntity>> userEntitiesByIds(
    Iterable<String> ids,
  ) async => {};

  @override
  Future<Map<String, UserPublicRecord>> userPublicRecordsByIds({
    required Iterable<String> ids,
    required Set<String> reciprocalPeerIds,
    Set<String> trustsViewerPeerIds = const {},
    Set<String> viewerTrustsPeerIds = const {},
    Map<String, MutualScoreRecord> scoresByPeerId = const {},
  }) async => {
    for (final id in ids)
      id: UserPublicRecord(
        id: id,
        displayName: id,
        description: '',
        userAvailability: null,
      ),
  };
}
