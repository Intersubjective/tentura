import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_tap_resolver.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';

import 'fixtures/constellation_reference_fixture.dart';

void main() {
  group('Constellation scene continuity', () {
    testWidgets(
      'tap resolver rejects stale geometry and accepts the repainted frame',
      (tester) async {
        final cubit = await loadReferenceCubit(
          field: ConstellationField(
            loadedAt: DateTime.utc(2026, 10, 8),
            context: '',
            requests: const [
              ConstellationRequest(
                id: 'req-ego-1',
                authorId: 'ego',
                title: 'Borrow tools',
                status: 0,
              ),
            ],
          ),
        );
        addTearDown(cubit.close);
        final holder = ConstellationPresentationFrameHolder();
        await pumpConstellationBody(
          tester,
          cubit,
          presentationFrameHolder: holder,
        );
        final controller = cubit.graphController;
        final graphFinder = find.byWidgetPredicate(
          (widget) => widget is GraphView<NodeDetails, EdgeDetails>,
        );
        final hitTester = tester
            .widget<GraphView<NodeDetails, EdgeDetails>>(graphFinder)
            .nodeTapHitTester!;
        const graphId = 'fr:req-ego-1';
        final paintedFrame = holder.frame!;
        final oldLabelPoint = paintedFrame.labels[graphId]!.center;
        expect(resolveConstellationTap(paintedFrame, oldLabelPoint), graphId);
        final snapshot = controller.renderSnapshot;
        final ticket = snapshot.layout!.ticket;
        final cameraRevision = controller.cameraRevision.value;
        final requests = controller.relayoutInvocationCount;
        final position = snapshot.resolvePosition(graphId)!;

        // Change only displayed geometry. Do not pump: the holder still
        // describes the previous paint, while hit testing sees the new scene.
        final movedPosition = ScenePoint(x: position.x + 40, y: position.y);
        controller.scene.beginPresentation(graphId, movedPosition);
        expect(controller.renderSnapshot.layout!.ticket, ticket);
        expect(controller.cameraRevision.value, cameraRevision);
        expect(controller.relayoutInvocationCount, requests);
        expect(
          hitTester(
            controller.viewportLocalToScene(oldLabelPoint),
            paintedFrame.paintOrder,
          ),
          isNull,
          reason:
              'A frame becomes stale when displayed geometry changes, '
              'even if the layout ticket and camera are unchanged',
        );

        await tester.pump();
        await tester.pump();
        final repaintedFrame = holder.frame!;
        expect(
          repaintedFrame.bodies[graphId]!.center,
          controller.sceneToViewportLocal(
            Offset(movedPosition.x, movedPosition.y),
          ),
          reason: 'The overlay must have painted the updated geometry',
        );
        final currentLabelPoint = repaintedFrame.labels[graphId]!.center;
        expect(
          resolveConstellationTap(repaintedFrame, currentLabelPoint),
          graphId,
        );
        final currentHitTester = tester
            .widget<GraphView<NodeDetails, EdgeDetails>>(graphFinder)
            .nodeTapHitTester!;
        expect(
          currentHitTester(
            controller.viewportLocalToScene(currentLabelPoint),
            repaintedFrame.paintOrder,
          ),
          graphId,
          reason: 'The current presentation frame must remain usable for taps',
        );
      },
    );

    testWidgets('label-only tap selects the request from the displayed frame', (
      tester,
    ) async {
      final cubit = await loadReferenceCubit(
        field: ConstellationField(
          loadedAt: DateTime.utc(2026, 10, 8),
          context: '',
          requests: const [
            ConstellationRequest(
              id: 'req-ego-1',
              authorId: 'ego',
              title: 'Borrow tools',
              status: 0,
            ),
          ],
        ),
      );
      addTearDown(cubit.close);
      final holder = ConstellationPresentationFrameHolder();
      await pumpConstellationBody(
        tester,
        cubit,
        presentationFrameHolder: holder,
      );

      const graphId = 'fr:req-ego-1';
      final frame = holder.frame!;
      final label = find.byKey(const ValueKey('constellation.label.$graphId'));
      expect(label, findsOneWidget);
      final labelPoint = frame.labels[graphId]!.center;
      expect(
        frame.bodies.values.any((body) => body.contains(labelPoint)),
        isFalse,
        reason: 'The tap must exercise label resolution, not a node body',
      );
      expect(
        frame.tapTargets.values.any((target) => target.contains(labelPoint)),
        isFalse,
        reason: 'The label must also be outside the fallback tap targets',
      );
      expect(resolveConstellationTap(frame, labelPoint), graphId);
      expect(cubit.state.selectedRequestId, isNull);

      // Reading the scene creates another snapshot without changing geometry.
      // The mounted hit tester must still accept the displayed label frame.
      final freshSnapshot = cubit.graphController.renderSnapshot;
      expect(freshSnapshot.resolvePosition(graphId), isNotNull);
      await tester.tapAt(tester.getCenter(label));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(cubit.state.selectedRequestId, 'req-ego-1');
      expect(
        find.byKey(const Key('constellation.request_preview')),
        findsOneWidget,
      );
    });

    testWidgets('rebuilding unchanged scene retains its layout algorithm', (
      tester,
    ) async {
      const viewport = Size(1200, 900);
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);
      await pumpConstellationBody(
        tester,
        cubit,
        size: viewport,
      );
      final controller = cubit.graphController;
      expect(controller.canLayout, isTrue);
      final requests = controller.relayoutInvocationCount;
      expect(requests, greaterThan(0));
      final graphFinder = find.byWidgetPredicate(
        (widget) => widget is GraphView<NodeDetails, EdgeDetails>,
      );
      final algorithm = tester
          .widget<GraphView<NodeDetails, EdgeDetails>>(graphFinder)
          .layoutAlgorithm;

      await pumpConstellationBody(
        tester,
        cubit,
        size: viewport,
      );

      expect(
        controller.relayoutInvocationCount,
        requests,
        reason: 'Unchanged layout inputs must retain algorithm identity',
      );
      expect(
        tester
            .widget<GraphView<NodeDetails, EdgeDetails>>(graphFinder)
            .layoutAlgorithm,
        same(algorithm),
        reason: 'One scene revision must retain one layout algorithm instance',
      );
    });
  });
}
