// `perf` suites are timing-sensitive, so like `mr` suites they run serialised
// (`-j 1`) and outside the default and plain-`pg` runs.
@Tags(['perf', 'pg', 'mr'])
library;

import 'package:test/test.dart';

import '../support/disposable_pg_target.dart';
import 'perf_fixture_matrix.dart';
import 'perf_fixture_report_expectations.dart';
import 'perf_fixtures.dart';

/// The matrix cases that read MeritRank (trust, reciprocal and fallback-score
/// populations) run in their own phase. One MeritRank graph is loaded per
/// disposable database, so each case checks the graph is non-empty before its
/// timings are taken, and must leave its JSON report in `build/perf`.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PERF_MATRIX_MR_TEST_DB',
    defaultNamePrefix: 'tentura_test_perf_matrix_mr',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for perf matrix test';

  group('MeritRank perf fixture matrix cases', () {
    test('are the trust and fallback-score cases', () {
      expect(
        PerfFixtureMatrix.cases.where((c) => c.requiresMeritRank),
        isNotEmpty,
      );
    });

    for (final c in PerfFixtureMatrix.cases.where((c) => c.requiresMeritRank)) {
      test(
        '${c.name} writes build/perf/${c.name}.json',
        () async {
          final session = await setUpDisposablePgWriter(
            target: target,
            createPgmer2Extension: true,
          );
          addTearDown(() => tearDownDisposablePgWriter(session: session));

          final seed = await c.seed(session.writer);
          await requireNonEmptyMeritRankGraph(session.writer);
          final file = await c.record(
            session: session,
            seed: seed,
            attempts: 3,
          );

          expectReportWritten(c, written: file, minAttempts: 3);
        },
        timeout: const Timeout(Duration(minutes: 60)),
        skip: skipReason,
      );
    }
  });
}
