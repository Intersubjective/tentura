@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_graph_scene.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_tap_resolver.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_camera_controls.dart';

import 'fixtures/constellation_reference_fixture.dart';

const _chipKey = Key('constellation.overflow.ego');

Future<ConstellationCubit> _expandRequests(
  WidgetTester tester,
  ConstellationPresentationFrameHolder holder,
) async {
  final cubit = await loadReferenceCubit(
    field: ConstellationField(
      loadedAt: DateTime.utc(2026, 10, 28),
      context: '',
      requests: [
        for (var i = 0; i < 37; i++)
          ConstellationRequest(
            id: 'request-$i',
            authorId: 'ego',
            title: 'Request $i',
            status: 0,
            isMine: true,
          ),
      ],
    ),
  );
  addTearDown(cubit.close);
  await pumpConstellationBody(
    tester,
    cubit,
    size: const Size(1200, 900),
    locale: const Locale('en'),
    presentationFrameHolder: holder,
    disableAnimations: true,
  );
  await tester.pumpAndSettle();
  expect(find.text('+34 more'), findsOneWidget);
  await tester.tap(find.text('+34 more'));
  await tester.pumpAndSettle();
  expect(find.text('Show fewer'), findsOneWidget);
  expect(
    cubit.graphController.renderSnapshot.topology.nodesById,
    hasLength(38),
  );
  return cubit;
}

Matrix4 _cameraMatrix(WidgetTester tester) => tester
    .widget<InteractiveViewer>(find.byType(InteractiveViewer))
    .transformationController!
    .value
    .clone();

// Geometry-only oracle: never invoke a camera fit action to obtain the target.
// Show fewer leaves the camera where Center view does: the owner at full
// scale in the middle of the usable viewport.
Matrix4 _collapsedFit(WidgetTester tester, ConstellationCubit cubit) {
  final controller = cubit.graphController;
  final owner = controller.renderSnapshot.resolvePosition(
    constellationGraphNodeIdForDomain('ego'),
  )!;
  final pixel = controller.viewportSize!;
  final insets = ConstellationCameraControls.cameraViewportInsets(
    tester.element(find.byType(ConstellationBody)),
    contextPanelVisible: false,
  );
  final usable = Rect.fromLTRB(
    insets.left,
    insets.top,
    pixel.width - insets.right,
    pixel.height - insets.bottom,
  );
  return Matrix4.identity()
    ..setEntry(0, 3, usable.center.dx - owner.x)
    ..setEntry(1, 3, usable.center.dy - owner.y);
}

void main() {
  group('Collapsing Field request overflow', () {
    testWidgets(
      'restores the overflow chip and collapsed camera fit without recentering',
      (
        tester,
      ) async {
        final holder = ConstellationPresentationFrameHolder();
        final cubit = await _expandRequests(tester, holder);
        final controller = cubit.graphController;
        final expandedCamera = _cameraMatrix(tester);
        final expandedOutcome = controller.scene.layoutOutcome;
        await tester.tap(find.text('Show fewer'));
        // Inspect the first presentation of the successful collapse layout.
        // Never wait for chip visibility: that would permit a later recovery
        // rebuild to satisfy the assertion. Reduced motion removes tweening.
        var presentedCollapse = false;
        for (var frame = 0; frame < 12; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          final outcome = controller.scene.layoutOutcome;
          if (outcome is GraphLayoutOutcomeSucceeded &&
              !identical(outcome, expandedOutcome) &&
              (holder.frame?.snapshot as GraphSceneSnapshot<Object?, Object?>?)
                      ?.sceneRevision ==
                  controller.sceneRevision) {
            presentedCollapse = true;
            break;
          }
        }
        expect(
          presentedCollapse,
          isTrue,
          reason:
              'collapse must present a successful new layout within 12 frames',
        );
        expect(
          controller.scene.layoutOutcome,
          isA<GraphLayoutOutcomeSucceeded>(),
        );
        expect(
          holder.frame!.chips,
          contains('ego'),
          reason:
              'the first collapse presentation must already contain the chip',
        );
        final collapseCamera = _cameraMatrix(tester);

        expect(
          cubit.graphController.renderSnapshot.topology.nodesById,
          hasLength(4),
        );
        expect(find.text('Show fewer'), findsNothing);
        expect(find.byKey(_chipKey), findsOneWidget);
        expect(find.text('+34 more'), findsOneWidget);
        final author = find.byKey(const Key('constellation.label.fp:ego'));
        expect(author, findsOneWidget);
        final viewport = tester.getRect(find.byType(ConstellationBody));
        final chipRect = tester.getRect(find.byKey(_chipKey));
        expect(viewport.contains(chipRect.topLeft), isTrue);
        expect(viewport.contains(chipRect.bottomRight), isTrue);
        expect(
          (chipRect.center - tester.getCenter(author)).distance,
          lessThan(chipRect.width + tester.getSize(author).height),
          reason: 'the restored chip belongs beside its author',
        );
        // This target is derived from the collapsed geometry and camera
        // constraints, independently of Show fewer and Fit all. No recovery
        // action can change the transform captured on the first presentation.
        final expectedCamera = _collapsedFit(tester, cubit);
        expect(
          expectedCamera.storage,
          isNot(orderedEquals(expandedCamera.storage)),
          reason: 'the collapsed fit must differ from the expanded fit',
        );
        expect(
          collapseCamera.storage,
          orderedEquals(
            expectedCamera.storage.map((value) => closeTo(value, 0.000001)),
          ),
          reason:
              'Show fewer must immediately restore the full collapsed fit transform',
        );
      },
    );
  });
}
