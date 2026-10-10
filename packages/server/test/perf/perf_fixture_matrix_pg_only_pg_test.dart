// `perf` suites are timing-sensitive, so like `mr` suites they run serialised
// (`-j 1`) and outside the default and plain-`pg` runs.
@Tags(['perf', 'pg', 'mr'])
library;

import 'package:test/test.dart';

import '../support/disposable_pg_target.dart';
import 'perf_fixture_matrix.dart';
import 'perf_fixture_report_expectations.dart';

/// The matrix cases that never read MeritRank (candidates, anchors, batches)
/// run in their own pg-only phase, on databases without `pgmer2`. Each one
/// must leave its JSON report in `build/perf`.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PERF_MATRIX_PG_ONLY_TEST_DB',
    defaultNamePrefix: 'tentura_test_perf_matrix_pg',
  );
  final reachable = await canReachPostgresAdmin(target);
  final attempts = perfMatrixAttempts();
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for perf matrix test';

  group('pg-only perf fixture matrix cases', () {
    test('are the cases that do not require MeritRank', () {
      expect(
        PerfFixtureMatrix.cases.where((c) => !c.requiresMeritRank),
        isNotEmpty,
      );
    });

    for (final c in PerfFixtureMatrix.cases.where(
      (c) => !c.requiresMeritRank,
    )) {
      test(
        '${c.name} writes build/perf/${c.name}.json',
        () async {
          final session = await setUpDisposablePgWriter(target: target);
          addTearDown(() => tearDownDisposablePgWriter(session: session));

          final seed = await c.seed(session.writer);
          final file = await c.record(
            session: session,
            seed: seed,
            attempts: attempts,
          );

          expectReportWritten(c, written: file, minAttempts: attempts);
        },
        timeout: const Timeout(Duration(minutes: 30)),
        skip: perfMatrixCaseSelected(c) ? skipReason : 'not selected',
      );
    }
  });
}
