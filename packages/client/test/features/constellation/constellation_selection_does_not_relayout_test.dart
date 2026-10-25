import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/scene/constellation_scene_controller.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/utils/tentura_layout_algorithms.dart';
import 'package:tentura/ui/utils/frame_slice_scheduler.dart';

import 'fixtures/constellation_reference_fixture.dart';

/// Holds the real Field layout job until metrics have arrived. Subsequent
/// jobs run normally, so selection-triggered layouts remain observable.
class _GatedFrameSliceScheduler extends Fake implements FrameSliceScheduler {
  bool Function(int)? _step;
  void Function()? _onComplete;
  var _released = false;

  @override
  void start({
    required bool Function(int units) step,
    required void Function() onComplete,
  }) {
    _step = step;
    _onComplete = onComplete;
    if (_released) _finish();
  }

  void release() {
    _released = true;
    _finish();
  }

  void _finish() {
    final step = _step;
    if (step == null) return;
    while (!step(1)) {}
    final onComplete = _onComplete;
    _step = null;
    _onComplete = null;
    onComplete?.call();
  }

  @override
  void cancelJob(void Function() onComplete) {
    if (identical(onComplete, _onComplete)) dispose();
  }

  @override
  void dispose() {
    _step = null;
    _onComplete = null;
  }
}

/// Layout work done by the scene so far: the cubit's reconciliations and the
/// graph controller's scene layout runs.
({int reconciliations, int layoutRuns}) _layoutWork(
  ConstellationCubit cubit,
) => (
  reconciliations: cubit.layoutReconciliationCount,
  layoutRuns: cubit.graphController.relayoutInvocationCount,
);

Future<ConstellationCubit> _mount(WidgetTester tester) async {
  final cubit = await loadReferenceCubit();
  addTearDown(cubit.close);
  await pumpConstellationBody(tester, cubit);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  return cubit;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group(
    'Person selection preserves settled layout after pending footprint metrics',
    () {
      for (final viewport in [const Size(1280, 800), const Size(390, 844)]) {
        testWidgets(
          'selecting and clearing a person keeps the algorithm and every node '
          'position at ${viewport.width.toInt()}x${viewport.height.toInt()}',
          (tester) async {
            final scheduler = _GatedFrameSliceScheduler();
            final scene = ConstellationSceneController(slicer: scheduler);
            final cubit = ConstellationCubit(
              case_: constellationCaseForField(constellationReferenceField()),
              viewer: kRefEgo,
              scene: scene,
            );
            addTearDown(cubit.close);
            await cubit.stream.firstWhere(
              (state) => state.status is StateIsSuccess,
            );
            final controller = cubit.graphController;
            const metrics = (
              labelGap: 8.0,
              personLabelWidth: 160.0,
              personLabelHeight: 24.0,
              requestLabelWidth: 200.0,
              requestLabelHeight: 44.0,
              chipWidth: 48.0,
              chipHeight: 24.0,
              badgeOverhang: 8.0,
            );
            await pumpConstellationBody(tester, cubit, size: viewport);
            expect(scene.awaitingLayoutOutcome, isTrue);
            expect(
              controller.scene.layoutOutcome,
              isA<GraphLayoutOutcomeRunning>(),
            );
            cubit.updateFootprintMetrics(metrics);
            expect(cubit.footprintMetricsForTest, metrics);
            scheduler.release();
            await tester.pumpAndSettle();

            expect(
              controller.scene.layoutOutcome,
              isA<GraphLayoutOutcomeSucceeded>(),
            );
            expect(scene.awaitingLayoutOutcome, isFalse);
            expect(controller.isLayoutSettling, isFalse);
            expect(cubit.layoutReconciliationCount, greaterThan(0));
            expect(controller.relayoutInvocationCount, greaterThan(0));

            final graphFinder = find.byWidgetPredicate(
              (widget) => widget is GraphView<NodeDetails, EdgeDetails>,
            );
            SceneLayoutAlgorithm mountedAlgorithm() => tester
                .widget<GraphView<NodeDetails, EdgeDetails>>(graphFinder)
                .layoutAlgorithm;
            final algorithm = cubit.graphSceneLayoutAlgorithm;
            expect(
              algorithm,
              isA<ConstellationSceneLayoutAlgorithm>()
                  .having(
                    (algorithm) => algorithm.footprints['am'],
                    'person footprint from pending metrics',
                    (left: 80.0, top: 28.0, right: 80.0, bottom: 52.0),
                  )
                  .having(
                    (algorithm) => algorithm.footprints['req-am-1'],
                    'Request footprint from pending metrics',
                    (left: 100.0, top: 26.0, right: 100.0, bottom: 70.0),
                  ),
              reason:
                  'The settled layout algorithm must use the pending person '
                  'and Request measurements before selection',
            );
            expect(
              mountedAlgorithm(),
              equals(algorithm),
              reason: 'GraphView must retain the settled scene algorithm',
            );
            final work = _layoutWork(cubit);
            final snapshot = controller.renderSnapshot;
            final positions = {
              for (final id in snapshot.topology.nodesById.keys)
                id: snapshot.resolvePosition(id),
            };
            expect(positions, isNotEmpty);
            expect(positions.values, everyElement(isNotNull));

            // Extra idle frames must leave the final layout unchanged before
            // selection is allowed to use it as its settled baseline.
            await _settle(tester);
            await tester.pumpAndSettle();
            expect(scene.awaitingLayoutOutcome, isFalse);
            expect(controller.isLayoutSettling, isFalse);
            expect(cubit.graphSceneLayoutAlgorithm, equals(algorithm));
            expect(mountedAlgorithm(), equals(algorithm));
            expect(_layoutWork(cubit), work);
            final idleSnapshot = controller.renderSnapshot;
            expect(
              {
                for (final id in idleSnapshot.topology.nodesById.keys)
                  id: idleSnapshot.resolvePosition(id),
              },
              equals(positions),
              reason:
                  'The settled baseline must stay stable across idle frames',
            );

            for (final selectedId in <String?>['am', null]) {
              cubit.selectPerson(selectedId);
              await tester.pumpAndSettle();

              final action = selectedId == null ? 'Clearing' : 'Selecting';
              expect(cubit.state.selectedPersonId, selectedId);
              expect(scene.awaitingLayoutOutcome, isFalse);
              expect(controller.isLayoutSettling, isFalse);
              expect(
                cubit.graphSceneLayoutAlgorithm,
                equals(algorithm),
                reason:
                    '$action a person must keep the settled scene algorithm',
              );
              expect(
                mountedAlgorithm(),
                equals(cubit.graphSceneLayoutAlgorithm),
                reason:
                    '$action a person must retain the scene algorithm in GraphView',
              );
              expect(
                _layoutWork(cubit),
                work,
                reason: '$action a person must not reconcile or run a layout',
              );
              final after = controller.renderSnapshot;
              expect(
                after.topology.nodesById.keys,
                unorderedEquals(positions.keys),
              );
              for (final entry in positions.entries) {
                expect(
                  after.resolvePosition(entry.key),
                  entry.value,
                  reason: '$action a person must not move ${entry.key}',
                );
              }
            }
          },
        );
      }
    },
  );

  group('Selection leaves the layout alone', () {
    testWidgets('selecting a Request runs no layout', (tester) async {
      final cubit = await _mount(tester);

      // Positive control: the initial load did lay the scene out.
      expect(cubit.layoutReconciliationCount, greaterThan(0));
      expect(cubit.graphController.relayoutInvocationCount, greaterThan(0));
      final before = _layoutWork(cubit);

      cubit.selectRequest('req-am-1');
      await _settle(tester);

      expect(cubit.state.selectedRequestId, 'req-am-1');
      final after = _layoutWork(cubit);
      expect(
        after.reconciliations,
        before.reconciliations,
        reason: 'Selecting a Request must not reconcile the layout',
      );
      expect(
        after.layoutRuns,
        before.layoutRuns,
        reason: 'Selecting a Request must not start a scene layout',
      );
    });

    testWidgets('moving the Request selection runs no layout', (tester) async {
      final cubit = await _mount(tester);
      cubit.selectRequest('req-am-1');
      await _settle(tester);
      final before = _layoutWork(cubit);

      cubit.selectRequest('req-in-1');
      await _settle(tester);

      expect(cubit.state.selectedRequestId, 'req-in-1');
      final after = _layoutWork(cubit);
      expect(after.reconciliations, before.reconciliations);
      expect(after.layoutRuns, before.layoutRuns);
    });

    testWidgets('clearing the Request selection runs no layout', (
      tester,
    ) async {
      final cubit = await _mount(tester);
      cubit.selectRequest('req-am-1');
      await _settle(tester);
      final before = _layoutWork(cubit);

      cubit.selectRequest(null);
      await _settle(tester);

      expect(cubit.state.selectedRequestId, isNull);
      final after = _layoutWork(cubit);
      expect(after.reconciliations, before.reconciliations);
      expect(after.layoutRuns, before.layoutRuns);
    });

    testWidgets('selecting a person runs no layout', (tester) async {
      final cubit = await _mount(tester);
      final before = _layoutWork(cubit);

      cubit.selectPerson('am');
      await _settle(tester);

      expect(cubit.state.selectedPersonId, 'am');
      final after = _layoutWork(cubit);
      expect(
        after.reconciliations,
        before.reconciliations,
        reason: 'Selecting a person must not reconcile the layout',
      );
      expect(
        after.layoutRuns,
        before.layoutRuns,
        reason: 'Selecting a person must not start a scene layout',
      );
    });
  });
}
