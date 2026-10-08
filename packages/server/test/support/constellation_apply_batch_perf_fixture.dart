import 'package:test/test.dart';

import '../perf/perf_fixture_matrix.dart';

const applyBatchPerfSuite = 'constellation_apply_batch_budgets_pg_test.dart';
const applyBatchWarmBudgetsMs = {1: (30, 70), 64: (100, 300)};
const applyBatchCursorHoldBudgetMs = 50;

/// Select a measured applyBatch case, rather than U41's legacy batches that
/// manually loop over anchor INSERTs without the production batch protocol.
PerfFixtureCase requireApplyBatchPerfFixture(int batch) {
  final matches = PerfFixtureMatrix.cases
      .where(
        (fixture) =>
            fixture.family == PerfFixtureFamily.batches &&
            fixture.requiresMeritRank &&
            fixture.parameters['operation'] == 'applyBatch' &&
            fixture.parameters['batch'] == batch &&
            fixture.parameters['visibleUsers'] == 1000 &&
            fixture.parameters['trust'] == 'dense' &&
            fixture.parameters['temperature'] == 'warm' &&
            fixture.parameters['costKind'] == 'meaningful-write',
      )
      .toList();
  expect(
    matches,
    hasLength(1),
    reason:
        'U41 matrix needs one real-MR warm $batch-op applyBatch fixture '
        'on the frozen-budget dense dataset',
  );
  return matches.single;
}
