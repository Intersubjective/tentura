// Measured applyBatch gates run serially in the existing MR perf phase.
@Tags(['perf', 'pg', 'mr'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../support/constellation_apply_batch_perf_fixture.dart';
import '../support/disposable_pg_target.dart';
import '../support/pg_wait.dart';
import 'perf_fixture_report_expectations.dart';
import 'perf_fixtures.dart';

/// Hold a read-only backend active throughout recording so WAL attribution is
/// deterministic even when this suite shares a cluster with other workloads.
Future<T> _withActiveSession<T>(
  Connection writer,
  Connection other,
  Future<T> Function() record,
) async {
  int? pid;
  try {
    pid =
        (await other.execute('SELECT pg_backend_pid()')).single.single! as int;
    final sleeping = other.execute('SELECT pg_sleep(600)');
    unawaited(sleeping.then<void>((_) {}, onError: (Object _) {}));
    final deadline = DateTime.now().add(kStableStateWait);
    while (true) {
      final active = await writer.execute(
        Sql.named('''
SELECT 1 FROM pg_stat_activity
WHERE datname = current_database() AND pid = @pid
  AND state = 'active' AND wait_event = 'PgSleep'
'''),
        parameters: {'pid': pid},
      );
      if (active.isNotEmpty) break;
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('WAL attribution backend did not become active');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return await record();
  } finally {
    try {
      if (pid != null) {
        await writer.execute(
          Sql.named('SELECT pg_cancel_backend(@pid)'),
          parameters: {'pid': pid},
        );
      }
    } finally {
      await other.close();
    }
  }
}

Iterable<Map<String, Object?>> _objects(Object? value) sync* {
  if (value is Map<String, Object?>) {
    yield value;
    for (final child in value.values) {
      yield* _objects(child);
    }
  } else if (value is List) {
    for (final child in value) {
      yield* _objects(child);
    }
  }
}

void _expectExecutedMutationPlans(Map<String, Object?> report) {
  final captures = (report['explain']! as List).cast<Map<String, Object?>>();
  for (final relation in [
    'constellation_anchor',
    'constellation_anchor_cursor',
    'constellation_anchor_target_watermark',
    'constellation_anchor_op_log',
  ]) {
    expect(
      captures.any((capture) {
        final nodes = _objects(capture['plan']).toList();
        return capture['rolledBack'] == true &&
            nodes.any(
              (node) =>
                  node['Node Type'] == 'ModifyTable' &&
                  node['Relation Name'] == relation,
            ) &&
            nodes.any((node) => node.containsKey('Actual Total Time')) &&
            nodes.any(
              (node) => node.keys.any((key) => key.startsWith('Shared ')),
            ) &&
            nodes.any((node) => node.containsKey('WAL Bytes'));
      }),
      isTrue,
      reason: '$relation needs a fresh ANALYZE/BUFFERS/WAL mutation capture',
    );
  }
}

/// Committed OK op-log rows of the measured attempts (`perf-b…` ids; the
/// unmetered warm-up calls use `perf-w…`) and their tuple bytes.
Future<(int, int)> _operationLogFootprint(
  Connection writer,
  String viewer,
) async {
  final result = await writer.execute(
    Sql.named('''
SELECT count(*)::int, coalesce(sum(pg_column_size(log)), 0)::bigint
FROM public.constellation_anchor_op_log log
WHERE viewer_id = @viewer AND result->>'status' = 'OK'
  AND client_op_id LIKE 'perf-b%'
'''),
    parameters: {'viewer': viewer},
  );
  return (
    int.parse(result.single[0].toString()),
    int.parse(result.single[1].toString()),
  );
}

void main() {
  group('measured applyBatch performance budgets', () {
    for (final batch in [1, 64]) {
      test('$batch-op production batch records live percentiles, WAL and '
          'operation-log bytes on the U41 dense fixture', () async {
        // Selection must fail before any PG reachability/skip check when the
        // production benchmark is missing. A hand-written JSON cannot pass.
        final fixture = requireApplyBatchPerfFixture(batch);
        final target = DisposablePgTarget.fromNamedEnvironment(
          envVarName: 'TENTURA_APPLY_BATCH_PERF_TEST_DB',
          defaultNamePrefix: 'tentura_test_apply_batch_perf',
        );
        final session = await setUpDisposablePgWriter(
          target: target,
          createPgmer2Extension: true,
        );
        addTearDown(() => tearDownDisposablePgWriter(session: session));
        final seed = await fixture.seed(session.writer);
        await requireNonEmptyMeritRankGraph(session.writer);
        expect(await _operationLogFootprint(session.writer, seed.viewerId), (
          0,
          0,
        ));

        // Remove stale evidence and always invoke the matrix's real recorder.
        final stale = File('build/perf/${fixture.name}.json');
        if (stale.existsSync()) stale.deleteSync();
        final written = await _withActiveSession(
          session.writer,
          await Connection.open(
            target.databaseEnv.pgEndpoint,
            settings: target.databaseEnv.pgEndpointSettings,
          ),
          () => fixture.record(session: session, seed: seed, attempts: 30),
        );
        expectReportWritten(fixture, written: written, minAttempts: 30);
        final report =
            jsonDecode(written.readAsStringSync()) as Map<String, Object?>;
        final attempts = reportObject(report, 'attempts');
        final succeeded = reportNumber(attempts, 'succeeded');
        expect(succeeded, greaterThan(0));
        expect(reportNumber(attempts, 'total'), 30);
        expect(reportNumber(attempts, 'failed') + succeeded, 30);

        final (p50Budget, p95Budget) = applyBatchWarmBudgetsMs[batch]!;
        final latency = reportObject(report, 'latencyMs');
        expect(reportNumber(latency, 'p50'), greaterThan(0));
        expect(reportNumber(latency, 'p50'), lessThanOrEqualTo(p50Budget));
        expect(reportNumber(latency, 'p95'), lessThanOrEqualTo(p95Budget));
        expect(
          reportNumber(latency, 'p95'),
          greaterThanOrEqualTo(reportNumber(latency, 'p50')),
        );
        final hold = reportNumber(reportObject(report, 'cursorHoldMs'), 'p95');
        expect(
          hold,
          greaterThan(0),
          reason: 'Production cursor hold must be metered',
        );
        expect(hold, lessThanOrEqualTo(applyBatchCursorHoldBudgetMs));
        expect(
          reportObject(report, 'parameters')['failedAttemptsIncluded'],
          true,
        );
        expect(
          reportObject(report, 'parameters')['latencyScope'],
          'admission-through-response-encoding',
        );

        // Validate the report against committed rows in this new database,
        // rather than trusting declared operation counts in a JSON artifact.
        final (rows, tupleBytes) = await _operationLogFootprint(
          session.writer,
          seed.viewerId,
        );
        expect(rows, succeeded * batch);
        expect(tupleBytes, greaterThan(0));
        final amplification = reportObject(report, 'writeAmplification');
        expect(reportNumber(amplification, 'acceptedOperations'), rows);
        expect(reportNumber(amplification, 'opLogRows'), rows);
        expect(reportNumber(amplification, 'opLogTupleBytes'), tupleBytes);
        final walBytes = reportNumber(
          reportObject(report, 'walBytes'),
          'total',
        );
        expect(walBytes / rows, greaterThan(0));
        // Cluster LSN deltas include unrelated sessions' WAL. The controlled
        // active backend requires honest cluster-total reporting, while the row
        // footprint and executed mutation plans above remain workload-specific.
        expect(report['walAttribution'], 'cluster-total');
        _expectExecutedMutationPlans(report);
      }, timeout: const Timeout(Duration(minutes: 60)));
    }
  });
}
