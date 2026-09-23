import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_camera_controls.dart';
import 'package:tentura/features/graph/ui/utils/graph_scene_ids.dart';
import 'package:tentura/ui/test_ids.dart';

import 'fixtures/constellation_reference_fixture.dart';

Matrix4 _cameraMatrix(WidgetTester tester) {
  final viewer = tester.widget<InteractiveViewer>(
    find.byType(InteractiveViewer),
  );
  return viewer.transformationController!.value.clone();
}

Rect _usableViewport(
  WidgetTester tester,
  ConstellationCubit cubit, {
  required bool personPanelVisible,
}) {
  final context = tester.element(find.byType(ConstellationBody));
  final insets = ConstellationCameraControls.cameraViewportInsets(
    context,
    personPanelVisible: personPanelVisible,
  );
  final pixel = cubit.graphController.viewportSize!;
  return Rect.fromLTRB(
    insets.left,
    insets.top,
    pixel.width - insets.right,
    pixel.height - insets.bottom,
  );
}

Rect _sceneNodeRect(ConstellationCubit cubit, String graphId) {
  final snapshot = cubit.graphController.renderSnapshot;
  final point = snapshot.resolvePosition(graphId);
  final sceneNode = snapshot.topology.nodesById[graphId];
  if (point == null || sceneNode == null) {
    return Rect.zero;
  }
  final bounds = constellationPlacedNodeBounds(
    centre: (x: point.x, y: point.y),
    footprint: cubit.layoutFootprints[graphId],
    size: (
      width: sceneNode.size.width,
      height: sceneNode.size.height,
    ),
  );
  return Rect.fromLTRB(
    bounds.left,
    bounds.top,
    bounds.right,
    bounds.bottom,
  );
}

void _expectFootprintsInsideUsable(
  WidgetTester tester,
  ConstellationCubit cubit, {
  required bool personPanelVisible,
}) {
  final controller = cubit.graphController;
  final usable = _usableViewport(
    tester,
    cubit,
    personPanelVisible: personPanelVisible,
  );
  for (final graphId in controller.renderSnapshot.topology.nodesById.keys) {
    if (controller.renderSnapshot.resolvePosition(graphId) == null) {
      continue;
    }
    final sceneRect = _sceneNodeRect(cubit, graphId);
    final topLeft = controller.sceneToViewportLocal(sceneRect.topLeft);
    final bottomRight =
        controller.sceneToViewportLocal(sceneRect.bottomRight);
    final viewportRect = Rect.fromPoints(topLeft, bottomRight);
    expect(
      usable.left - 1,
      lessThanOrEqualTo(viewportRect.left),
      reason: '$graphId left outside usable',
    );
    expect(
      usable.top - 1,
      lessThanOrEqualTo(viewportRect.top),
      reason: '$graphId top outside usable',
    );
    expect(
      viewportRect.right,
      lessThanOrEqualTo(usable.right + 1),
      reason: '$graphId right outside usable',
    );
    expect(
      viewportRect.bottom,
      lessThanOrEqualTo(usable.bottom + 1),
      reason: '$graphId bottom outside usable',
    );
  }
}

Future<void> _disorientCamera(ConstellationCubit cubit) async {
  final controller = cubit.graphController;
  controller.zoomBy(0.3);
  const egoGraphId = '${TenturaGraphNodeKind.fieldPerson}:ego';
  final egoPoint = controller.renderSnapshot.resolvePosition(egoGraphId);
  if (egoPoint != null) {
    controller.jumpToPosition(
      Offset(egoPoint.x + 280, egoPoint.y + 220),
    );
  }
}

void main() {
  group('ConstellationCameraControls', () {
    testWidgets('fit whole field after zoom and pan', (tester) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);

      await pumpConstellationBody(tester, cubit);
      await tester.pumpAndSettle();

      await _disorientCamera(cubit);
      await tester.pump();

      await tester.tap(find.byKey(TestIds.key(TestIds.constellationFitAll)));
      await tester.pump();

      _expectFootprintsInsideUsable(tester, cubit, personPanelVisible: false);
      expect(cubit.graphController.cameraScale, lessThanOrEqualTo(1.0));
    });

    testWidgets('center on ego restores scale and centres in usable region', (
      tester,
    ) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);

      await pumpConstellationBody(tester, cubit);
      await tester.pumpAndSettle();

      await _disorientCamera(cubit);
      await tester.pump();

      await tester.tap(
        find.byKey(TestIds.key(TestIds.constellationCenterOnMe)),
      );
      await tester.pump();

      expect(cubit.graphController.cameraScale, closeTo(1.0, 0.001));
      final usable = _usableViewport(tester, cubit, personPanelVisible: false);
      const egoGraphId = '${TenturaGraphNodeKind.fieldPerson}:ego';
      final egoScene = cubit.graphController.renderSnapshot
          .resolvePosition(egoGraphId)!;
      final egoViewport = cubit.graphController.sceneToViewportLocal(
        Offset(egoScene.x, egoScene.y),
      );
      expect(egoViewport.dx, closeTo(usable.center.dx, 0.5));
      expect(egoViewport.dy, closeTo(usable.center.dy, 0.5));
    });

    testWidgets('controls disabled during draggingExisting', (tester) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);

      await pumpConstellationBody(tester, cubit);
      await tester.pumpAndSettle();

      await _disorientCamera(cubit);
      await tester.pump();
      final matrixBefore = _cameraMatrix(tester);

      cubit.beginDragExisting(
        target: ConstellationAnchorTarget.person('am'),
      );
      await tester.pump();

      final fitButton = tester.widget<IconButton>(
        find.byKey(TestIds.key(TestIds.constellationFitAll)),
      );
      final centerButton = tester.widget<IconButton>(
        find.byKey(TestIds.key(TestIds.constellationCenterOnMe)),
      );
      expect(fitButton.onPressed, isNull);
      expect(centerButton.onPressed, isNull);

      await tester.tap(find.byKey(TestIds.key(TestIds.constellationFitAll)));
      await tester.tap(
        find.byKey(TestIds.key(TestIds.constellationCenterOnMe)),
      );
      await tester.pump();

      expect(
        _cameraMatrix(tester).storage,
        matrixBefore.storage,
      );
    });

    testWidgets('single-node ego-only field fits without degenerate crash', (
      tester,
    ) async {
      final field = ConstellationField(
        loadedAt: DateTime.utc(2026, 9, 9),
        context: '',
        peers: const [],
        edges: const [],
        requests: const [],
      );
      final cubit = await loadReferenceCubit(field: field);
      addTearDown(cubit.close);

      await pumpConstellationBody(tester, cubit);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(TestIds.key(TestIds.constellationFitAll)));
      await tester.pump();

      expect(cubit.graphController.cameraScale, closeTo(1.0, 0.001));
      expect(tester.takeException(), isNull);
    });

    testWidgets('camera transform stable across field mutations', (
      tester,
    ) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);

      await pumpConstellationBody(tester, cubit);
      await tester.pumpAndSettle();

      final baseline = _cameraMatrix(tester);

      void expectUnchanged() {
        expect(
          _cameraMatrix(tester).storage,
          baseline.storage,
          reason: 'camera moved unexpectedly',
        );
      }

      cubit.toggleSatelliteOverflow('ego');
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expectUnchanged();

      cubit.setFilterCapabilitySlugs({'tools'});
      await tester.pumpAndSettle();
      expectUnchanged();

      cubit.setViewMode(ConstellationViewMode.text);
      await tester.pumpAndSettle();
      cubit.setViewMode(ConstellationViewMode.map);
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expectUnchanged();

      await cubit.load();
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expectUnchanged();
    });
  });
}
