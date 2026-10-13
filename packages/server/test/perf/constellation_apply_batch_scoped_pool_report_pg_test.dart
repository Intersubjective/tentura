// The measured applyBatch report must describe the production scoped main
// pool (MainDbPool, one leased connection per scope, capacity 4 as dev runs
// it) and attribute latency to lease waits, admission waits or lane time.
@Tags(['perf', 'pg', 'mr'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../support/constellation_apply_batch_perf_fixture.dart';
import '../support/disposable_pg_target.dart';
import 'perf_fixtures.dart';

void main() {
  group('measured applyBatch on the scoped main pool', () {
    for (final batch in [1, 64]) {
      test('$batch-op report records pool kind and capacity and meets the '
          'warm budgets', () async {
        final fixture = requireApplyBatchPerfFixture(batch);
        final target = DisposablePgTarget.fromNamedEnvironment(
          envVarName: 'TENTURA_APPLY_BATCH_SCOPED_REPORT_TEST_DB',
          defaultNamePrefix: 'tentura_test_apply_batch_scoped_report',
        );
        final session = await setUpDisposablePgWriter(
          target: target,
          createPgmer2Extension: true,
        );
        addTearDown(() => tearDownDisposablePgWriter(session: session));
        final seed = await fixture.seed(session.writer);
        await requireNonEmptyMeritRankGraph(session.writer);

        final written = await fixture.record(
          session: session,
          seed: seed,
          attempts: 30,
        );
        final report =
            jsonDecode(written.readAsStringSync()) as Map<String, Object?>;
        final parameters = report['parameters']! as Map<String, Object?>;
        expect(parameters['poolKind'], 'scoped-main-pool');
        expect(parameters['poolCapacity'], 4);

        // The report must attribute latency: time waiting for a pool
        // connection lease and for scope admission, versus time inside the
        // serialised database lane.
        final pool = report['poolDiagnostics'];
        expect(pool, isA<Map<String, Object?>>());
        final diagnostics = pool! as Map<String, Object?>;
        for (final key in ['leaseWaitMs', 'admissionWaitMs', 'laneBusyMs']) {
          final stat = diagnostics[key];
          expect(stat, isA<Map<String, Object?>>(), reason: key);
          expect((stat! as Map<String, Object?>)['p95'], isA<num>());
        }

        final (p50Budget, p95Budget) = applyBatchWarmBudgetsMs[batch]!;
        final latency = report['latencyMs']! as Map<String, Object?>;
        expect(latency['p50']! as num, lessThanOrEqualTo(p50Budget));
        expect(latency['p95']! as num, lessThanOrEqualTo(p95Budget));

        // Parity with the raw-pool gate: production cursor hold is metered.
        final hold = (report['cursorHoldMs']! as Map<String, Object?>)['p95'];
        expect(hold! as num, greaterThan(0));
        expect(hold, lessThanOrEqualTo(applyBatchCursorHoldBudgetMs));

        // Attribution must be real: the lane did work, no wait exceeds the
        // end-to-end p95, and the report names what dominates latency.
        num p95(String key) =>
            (diagnostics[key]! as Map<String, Object?>)['p95']! as num;
        expect(p95('laneBusyMs'), greaterThan(0));
        for (final key in ['leaseWaitMs', 'admissionWaitMs']) {
          expect(p95(key), greaterThanOrEqualTo(0));
          expect(p95(key), lessThanOrEqualTo(latency['p95']! as num));
        }
        final dominant = diagnostics['dominantLatencyCause'];
        expect(
          dominant,
          anyOf('lease-wait', 'admission-wait', 'serialised-lane', 'none'),
        );
        if (p95('leaseWaitMs') + p95('admissionWaitMs') > p95('laneBusyMs')) {
          expect(dominant, isNot('serialised-lane'));
        }
        expect(File(written.path).existsSync(), isTrue);
      }, timeout: const Timeout(Duration(minutes: 30)));
    }
  });
}
