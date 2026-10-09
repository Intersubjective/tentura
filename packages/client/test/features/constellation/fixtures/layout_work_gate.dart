// The production counter API is read dynamically on purpose: while it is
// absent the gate tests fail with an assertion about the missing API instead
// of a compile error that stops every test description from loading.
// ignore_for_file: avoid_catching_errors

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/layout/constellation_layout_engine.dart';

/// The bound may exceed the largest step work observed on the real N=1000
/// jobs by at most this factor; a looser bound would let an all-nodes unit
/// slip through.
const layoutWorkBoundHeadroom = 2;

/// Counted work of the latest `step` call: `LayoutJob.lastStepWork`, an
/// integer cost (nodes touched, index operations, edges visited) that depends
/// only on the inputs and never on the host clock.
int lastStepWorkOf(LayoutJob job) {
  try {
    return (job as dynamic).lastStepWork as int;
  } on NoSuchMethodError {
    fail('LayoutJob must expose lastStepWork, the work counted by step().');
  }
}

/// Calibrated per-step work bound: `LayoutJob.unitWorkBound`.
int unitWorkBoundOf(LayoutJob job) {
  try {
    return (job as dynamic).unitWorkBound as int;
  } on NoSuchMethodError {
    fail('LayoutJob must expose unitWorkBound, the calibrated step bound.');
  }
}

/// Counted work of every `step(1)` call until [job] completes.
List<int> stepWorkCounts(LayoutJob job) => countStepWork(
  step: job.step,
  workOfLastStep: () => lastStepWorkOf(job),
);

/// [stepWorkCounts] for anything that steps and reports work, e.g. a fake.
List<int> countStepWork({
  required bool Function(int units) step,
  required int Function() workOfLastStep,
  int maxSteps = 10000000,
}) {
  final counts = <int>[];
  for (var call = 0; call < maxSteps; call++) {
    final done = step(1);
    counts.add(workOfLastStep());
    if (done) return counts;
  }
  throw StateError('Layout job did not finish after $maxSteps calls');
}

/// The one gate every layout step must pass: counted work within [bound].
/// Shared by the bench and the fake-step tests.
void expectStepWorkWithinBound(
  List<int> counts, {
  required int bound,
  String label = 'job',
}) {
  final violations = [
    for (var i = 0; i < counts.length; i++)
      if (counts[i] > bound) 'step $i counted ${counts[i]} > $bound',
  ];
  expect(violations, isEmpty, reason: '$label exceeded the work bound');
}

/// The bound must be calibrated to [observedMax], the largest counted step
/// work of the real job: not below it, and not loose by more than
/// [layoutWorkBoundHeadroom].
void expectBoundCalibratedTo(int bound, int observedMax) {
  expect(observedMax, greaterThan(0), reason: 'real job must count work');
  expect(bound, greaterThanOrEqualTo(observedMax));
  expect(bound, lessThanOrEqualTo(observedMax * layoutWorkBoundHeadroom));
}
