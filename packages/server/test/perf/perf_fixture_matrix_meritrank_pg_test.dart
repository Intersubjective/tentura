// `perf` suites are timing-sensitive, so like `mr` suites they run serialised
// (`-j 1`) and outside the default and plain-`pg` runs.
@Tags(['perf', 'pg', 'mr', 'multi-connection'])
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
  final skipReason = await pgSkipReason(target);
  final attempts = perfMatrixAttempts();

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
            attempts: attempts,
          );

          expectReportWritten(c, written: file, minAttempts: attempts);
        },
        timeout: const Timeout(Duration(minutes: 60)),
        skip: perfMatrixCaseSelected(c) ? skipReason : 'not selected',
      );
    }
    for (final c in PerfFixtureMatrix.cases.where((c) => c.requiresMeritRank)) {
      test(
        '${c.name} seeds one trust row per mirrored MeritRank edge',
        () async {
          final session = await setUpDisposablePgWriter(
            target: target,
            createPgmer2Extension: true,
          );
          addTearDown(() => tearDownDisposablePgWriter(session: session));

          await c.seed(session.writer);
          await requireNonEmptyMeritRankGraph(session.writer);

          // Observe the seed before record(), warm-up, workers or EXPLAIN can
          // change the database. Upf users form the shared trust fixture;
          // fallback-score cases also add separate Upg users and votes.
          final counts = (await session.writer.execute('''
SELECT
  (SELECT count(*)::int FROM mr_edgelist() e
   WHERE e.src LIKE 'Upf%' AND e.dst LIKE 'Upf%'
     AND e.src <> e.dst AND e.weight > 0),
  (SELECT count(*)::int FROM public.user_trust_edge
   WHERE subject LIKE 'Upf%' AND object LIKE 'Upf%')
''')).single;
          final mirroredMeritRankEdges = counts[0]! as int;
          final trustRows = counts[1]! as int;

          expect(
            mirroredMeritRankEdges,
            greaterThan(0),
            reason: '${c.name} must seed a nonempty trust graph',
          );
          expect(
            trustRows,
            mirroredMeritRankEdges,
            reason:
                '${c.name} must mirror the trust graph during seeding, '
                'before the first timed attempt',
          );
        },
        timeout: const Timeout(Duration(minutes: 10)),
        skip: skipReason,
      );
    }
  });
}
