import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/layout/constellation_layout_engine.dart';
import 'package:tentura/features/constellation/domain/layout/spatial_index.dart';

import 'fixtures/layout_work_gate.dart';
import 'fixtures/resumable_layout_inputs.dart';

/// Stand-in for a layout unit that walks every node instead of a bounded
/// batch: its counted work grows with the field size.
final class _UnboundedStepper {
  _UnboundedStepper(this.unboundedWork);

  final int unboundedWork;
  int _calls = 0;
  int _lastWork = 0;

  bool step(int units) {
    _calls++;
    _lastWork = _calls == 2 ? unboundedWork * units : units;
    return _calls >= 3;
  }

  int get lastStepWork => _lastWork;
}

ConstellationLayoutEngine _engine() =>
    ConstellationLayoutEngine(newIndex: BruteForceIndex.new);

LayoutJob _startJob({required bool incremental}) {
  final input = syntheticLayoutInput(1000);
  final next = withLayoutChanges(
    input,
    anchors: {
      for (final anchor in input.anchorByNodeId.entries)
        anchor.key: layoutAnchor(-anchor.value.xUnits, -anchor.value.yUnits),
    },
  );
  final previous = _engine().start(null, input);
  while (!previous.step(1000000)) {}
  return _engine().start(
    incremental ? previous.result : null,
    incremental ? next : input,
  );
}

void main() {
  group('layout job counted work gate', () {
    test('fails the gate for a step that walks every node', () {
      final nodeCount = syntheticLayoutInput(1000).nodeSizes.length;
      final stepper = _UnboundedStepper(nodeCount);
      final counts = countStepWork(
        step: stepper.step,
        workOfLastStep: () => stepper.lastStepWork,
      );
      expect(counts, [1, nodeCount, 1]);
      final bound = unitWorkBoundOf(_startJob(incremental: false));
      expect(
        () => expectStepWorkWithinBound(counts, bound: bound, label: 'fake'),
        throwsA(isA<TestFailure>()),
      );
    });

    test('fails the gate for a step one unit above the bound', () {
      final bound = unitWorkBoundOf(_startJob(incremental: false));
      final stepper = _UnboundedStepper(bound + 1);
      final counts = countStepWork(
        step: stepper.step,
        workOfLastStep: () => stepper.lastStepWork,
      );
      expect(
        () => expectStepWorkWithinBound(counts, bound: bound, label: 'fake'),
        throwsA(isA<TestFailure>()),
      );
    });

    test('passes the gate for a step exactly at the bound', () {
      final bound = unitWorkBoundOf(_startJob(incremental: false));
      expectStepWorkWithinBound([1, bound, 1], bound: bound, label: 'fake');
    });

    test('the bound is below the work of a unit visiting every node', () {
      final nodeCount = syntheticLayoutInput(1000).nodeSizes.length;
      expect(
        unitWorkBoundOf(_startJob(incremental: false)),
        lessThan(nodeCount),
      );
    });

    test('the bound is calibrated to the real jobs at 1000 nodes', () {
      final observedMax = [
        for (final incremental in [false, true])
          ...stepWorkCounts(_startJob(incremental: incremental)),
      ].reduce((a, b) => a > b ? a : b);
      expectBoundCalibratedTo(
        unitWorkBoundOf(_startJob(incremental: false)),
        observedMax,
      );
    });

    for (final incremental in [false, true]) {
      final mode = incremental ? 'incremental' : 'full';

      test('$mode job at 1000 nodes keeps every step within the bound', () {
        final counts = stepWorkCounts(_startJob(incremental: incremental));
        expect(counts.length, greaterThan(1));
        expectStepWorkWithinBound(
          counts,
          bound: unitWorkBoundOf(_startJob(incremental: incremental)),
          label: mode,
        );
      });

      test('$mode job counts identical work across 10 reruns', () {
        final first = stepWorkCounts(_startJob(incremental: incremental));
        for (var run = 1; run < 10; run++) {
          expect(
            stepWorkCounts(_startJob(incremental: incremental)),
            first,
            reason: 'run $run',
          );
        }
      });
    }
  });
}
