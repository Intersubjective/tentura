// MeritRank is shared across disposable databases; run these fixtures serially.
@Tags(['perf', 'pg', 'mr'])
library;

import 'package:test/test.dart';

import '../support/disposable_pg_target.dart';
import 'perf_fixture_matrix.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PERF_TRUST_EDGES_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_perf_trust_edges',
  );
  final skipReason = await pgSkipReason(target);

  group('perf fixtures have trust edges before the first timed attempt', () {
    for (final fixture in PerfFixtureMatrix.cases.where(
      (fixture) => fixture.requiresMeritRank,
    )) {
      test(
        '${fixture.name} seeds one trust row per mirrored MeritRank edge',
        () async {
          final session = await setUpDisposablePgWriter(
            target: target,
            createPgmer2Extension: true,
          );
          addTearDown(() => tearDownDisposablePgWriter(session: session));

          await fixture.seed(session.writer);

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
            reason: '${fixture.name} must seed a nonempty trust graph',
          );
          expect(
            trustRows,
            mirroredMeritRankEdges,
            reason:
                '${fixture.name} must mirror the trust graph during seeding, '
                'before the first timed attempt',
          );
        },
        timeout: const Timeout(Duration(minutes: 10)),
        skip: skipReason,
      );
    }
  });
}
