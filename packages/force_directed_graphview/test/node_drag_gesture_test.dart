import 'dart:ui' show Offset;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:force_directed_graphview/src/widget/graph_layout_view.dart';
import 'support/fixed_scene_layout.dart';
import 'support/int_graph_controller.dart';
import 'support/settle_graph_layout.dart';

void main() {
  const viewportSize = Size(800, 600);
  const canvasSize = Size(500, 500);

  testWidgets('orderedRenderNodeIds respects configured paint order',
      (tester) async {
    final controller = testIntIntGraphController();
    const a = Node<int>(data: 1, size: 10);
    const b = Node<int>(data: 2, size: 10);
    const c = Node<int>(data: 3, size: 10);

    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 600,
          child: GraphView<Node<int>, Edge<Node<int>, int>>(
            controller: controller,
            canvasSize: const GraphCanvasSize.fixed(Size(500, 500)),
            layoutAlgorithm: FixedSceneLayoutAlgorithm({
              '1': ScenePoint(x: 100, y: 100),
              '2': ScenePoint(x: 200, y: 200),
              '3': ScenePoint(x: 300, y: 300),
            }),
            nodeBuilder: (context, node) => SizedBox(
              width: node.size,
              height: node.size,
            ),
          ),
        ),
      ),
    );

    controller.reconcileTopology({a, b, c}, const {});
    await settleGraphLayout(tester, controller);

    controller.setNodePaintOrder(const ['3', '1']);
    final snapshot = controller.renderSnapshot;
    final ordered = controller
        .orderedRenderNodeIds(
          snapshot,
          configuredPaintOrder: const ['3', '1'],
        )
        .map((id) => int.parse(id))
        .toList();

    expect(ordered, [3, 1, 2]);
    controller.dispose();
  });

  testWidgets('pan and zoom without node capture', (tester) async {
    final controller = _TestHarness.newController();
    var dragUpdates = 0;

    await _pumpGraph(
      tester,
      controller: controller,
      onNodeDragUpdate: (_, __) => dragUpdates++,
    );

    final viewer =
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    viewer.transformationController!.value = Matrix4.identity()
      ..translateByDouble(-100, -100, 0, 1)
      ..scaleByDouble(2, 2, 1, 1);
    await tester.pump();
    final cameraBefore = viewer.transformationController!.value.clone();
    final emptyCanvasPoint = _globalForScene(tester, const Offset(80, 80));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.touch);
    await gesture.down(emptyCanvasPoint);
    await gesture.moveBy(const Offset(50, 20));
    await gesture.moveBy(const Offset(30, 20));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(viewer.transformationController!.value, isNot(cameraBefore));
    expect(dragUpdates, 0);
    expect(controller.isCameraGated, isFalse);

    final scaleBefore = controller.currentScale;
    controller.zoomBy(0.8);
    expect(controller.currentScale, lessThan(scaleBefore));

    controller.dispose();
  });

  testWidgets('touch hold without movement does not capture the node',
      (tester) async {
    final controller = _TestHarness.newController();
    Node<int>? dragged;

    await _pumpGraph(
      tester,
      controller: controller,
      onNodeDragStart: (node, _) => dragged = node,
    );

    final nodeCentre = _nodeCenter(tester, _TestHarness.bottom);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.touch);
    await gesture.down(nodeCentre);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(dragged, isNull);
    expect(controller.isCameraGated, isFalse);

    await gesture.up();
    await tester.pump();
    expect(controller.isCameraGated, isFalse);

    controller.dispose();
  });

  testWidgets('touch drag without a hold keeps the camera fixed',
      (tester) async {
    final controller = _TestHarness.newController();
    final updates = <Offset>[];

    await _pumpGraph(
      tester,
      controller: controller,
      onNodeDragUpdate: (_, position) => updates.add(position),
    );

    final nodeCentre = _nodeCenter(tester, _TestHarness.bottom);
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final cameraBefore = viewer.transformationController!.value.clone();
    final gesture = await tester.createGesture(kind: PointerDeviceKind.touch);

    await gesture.down(nodeCentre);

    await tester.pump();
    await gesture.moveBy(const Offset(80, 30));
    await tester.pump();

    expect(updates, isNotEmpty);
    expect(
      viewer.transformationController!.value.storage,
      orderedEquals(cameraBefore.storage),
    );

    await gesture.up();
    controller.dispose();
  });

  testWidgets('touch drag after camera zoom uses scene coordinates',
      (tester) async {
    final controller = _TestHarness.newController();
    await _pumpGraph(
      tester,
      controller: controller,
      onNodeDragUpdate: (_, __) {},
    );
    final viewer =
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    viewer.transformationController!.value = Matrix4.identity()
      ..translateByDouble(30, 40, 0, 1)
      ..scaleByDouble(1.5, 1.5, 1, 1);
    await tester.pump();
    final cameraBefore = viewer.transformationController!.value.clone();
    final sceneBefore = testNodePosition(controller, _TestHarness.bottom);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.touch);
    await gesture.down(_nodeCenter(tester, _TestHarness.bottom));
    await gesture.moveBy(const Offset(60, 30));
    await gesture.moveBy(const Offset(30, 15));
    await tester.pump();
    expect(testNodePosition(controller, _TestHarness.bottom),
        sceneBefore + const Offset(60, 30));
    expect(viewer.transformationController!.value.storage,
        orderedEquals(cameraBefore.storage));
    await gesture.up();
    controller.dispose();
  });

  testWidgets('transformNodeDragPosition clamps the presented centre',
      (tester) async {
    final controller = _TestHarness.newController();
    final updates = <Offset>[];
    await _pumpGraph(
      tester,
      controller: controller,
      onNodeDragUpdate: (_, position) => updates.add(position),
      transformNodeDragPosition: (_, proposed) {
        // Cap x at the node's start scene x + 20.
        final start = testNodePosition(controller, _TestHarness.bottom);
        if (proposed.dx > start.dx + 20) {
          return Offset(start.dx + 20, proposed.dy);
        }
        return proposed;
      },
    );
    final sceneBefore = testNodePosition(controller, _TestHarness.bottom);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.touch);
    await gesture.down(_nodeCenter(tester, _TestHarness.bottom));
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();
    expect(updates, isNotEmpty);
    expect(updates.last.dx, closeTo(sceneBefore.dx + 20, 0.5));
    expect(
      testNodePosition(controller, _TestHarness.bottom).dx,
      closeTo(sceneBefore.dx + 20, 0.5),
    );
    await gesture.up();
    controller.dispose();
  });

  testWidgets('touch node drag does not emit a tap', (tester) async {
    final controller = _TestHarness.newController();
    var taps = 0;
    await _pumpGraph(
      tester,
      controller: controller,
      onNodeDragUpdate: (_, __) {},
      onNodeTap: (_) => taps++,
    );
    final gesture = await tester.createGesture(kind: PointerDeviceKind.touch);
    final nodeCentre = _nodeCenter(tester, _TestHarness.bottom);
    await gesture.down(nodeCentre);
    await gesture.moveBy(const Offset(70, 30));
    await gesture.up();
    expect(taps, 0);
    await tester.pump();
    final tap = await tester.createGesture(kind: PointerDeviceKind.touch);
    await tap.down(_nodeCenter(tester, _TestHarness.bottom));
    await tap.moveBy(const Offset(2, 2));
    await tap.up();
    expect(taps, 1);
    controller.dispose();
  });

  testWidgets('touch on a node in a tap-only graph pans the camera',
      (tester) async {
    final controller = _TestHarness.newController();
    await _pumpGraph(tester, controller: controller, onNodeTap: (_) {});
    final viewer =
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    viewer.transformationController!.value = Matrix4.identity()
      ..translateByDouble(-100, -100, 0, 1)
      ..scaleByDouble(2, 2, 1, 1);
    await tester.pump();
    final cameraBefore = viewer.transformationController!.value.clone();
    final gesture = await tester.createGesture(kind: PointerDeviceKind.touch);
    await gesture.down(_nodeCenter(tester, _TestHarness.bottom));
    await gesture.moveBy(const Offset(70, 30));
    await gesture.moveBy(const Offset(50, 20));
    await tester.pump();
    expect(controller.isCameraGated, isFalse);
    expect(viewer.transformationController!.value, isNot(cameraBefore));
    await gesture.up();
    controller.dispose();
  });

  testWidgets('second touch after capture cannot move camera before a frame',
      (tester) async {
    final controller = _TestHarness.newController();
    await _pumpGraph(tester,
        controller: controller, onNodeDragUpdate: (_, __) {});
    final viewer =
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    viewer.transformationController!.value = Matrix4.identity()
      ..translateByDouble(-100, -100, 0, 1)
      ..scaleByDouble(2, 2, 1, 1);
    await tester.pump();
    final cameraBefore = viewer.transformationController!.value.clone();
    final point = _nodeCenter(tester, _TestHarness.bottom);
    final first = await tester.createGesture(kind: PointerDeviceKind.touch);
    await first.down(point);
    await first.moveBy(const Offset(50, 0));
    final second = await tester.createGesture(kind: PointerDeviceKind.touch);
    await second.down(point + const Offset(20, 20));
    await second.moveBy(const Offset(50, 0));
    await second.moveBy(const Offset(20, 0));
    expect(viewer.transformationController!.value.storage,
        orderedEquals(cameraBefore.storage));
    await first.up();
    await second.up();
    controller.dispose();
  });

  testWidgets('touch movement immediately captures the node', (tester) async {
    final controller = _TestHarness.newController();
    Node<int>? dragged;
    var dragUpdates = 0;

    await _pumpGraph(
      tester,
      controller: controller,
      onNodeDragStart: (node, _) => dragged = node,
      onNodeDragUpdate: (_, __) => dragUpdates++,
    );

    final nodeCentre = _nodeCenter(tester, _TestHarness.bottom);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.touch);
    await gesture.down(nodeCentre);
    await gesture.moveBy(Offset(kPanSlop + 1, 0));
    await tester.pump();

    expect(dragged, _TestHarness.bottom);
    expect(dragUpdates, greaterThan(0));
    expect(controller.isCameraGated, isTrue);

    await gesture.up();
    controller.dispose();
  });

  testWidgets(
      'two-pointer pinch before capture zooms camera and skips node drag',
      (tester) async {
    final controller = _TestHarness.newController();
    Node<int>? dragged;
    var dragUpdates = 0;

    await _pumpGraph(
      tester,
      controller: controller,
      onNodeDragStart: (node, _) => dragged = node,
      onNodeDragUpdate: (_, __) => dragUpdates++,
    );

    final nodeCentre = _nodeCenter(tester, _TestHarness.bottom);
    final gestureA = await tester.createGesture(kind: PointerDeviceKind.touch);
    await gestureA.down(nodeCentre);
    await tester.pump(const Duration(milliseconds: 100));

    final gestureB = await tester.createGesture(kind: PointerDeviceKind.touch);
    await gestureB.down(nodeCentre + const Offset(40, 0));
    final initialScale = controller.currentScale;
    await gestureA.moveBy(const Offset(-50, 0));
    await gestureB.moveBy(const Offset(50, 0));
    await gestureA.moveBy(const Offset(-30, 0));
    await gestureB.moveBy(const Offset(30, 0));
    await tester.pump();
    expect(controller.currentScale, greaterThan(initialScale));

    expect(dragged, isNull);
    expect(dragUpdates, 0);
    expect(controller.isCameraGated, isFalse);

    await gestureA.up();
    await gestureB.up();
    controller.dispose();
  });

  testWidgets('additional finger after capture keeps node ownership',
      (tester) async {
    final controller = _TestHarness.newController();
    final updates = <Offset>[];

    await _pumpGraph(
      tester,
      controller: controller,
      onNodeDragUpdate: (_, position) => updates.add(position),
    );

    final nodeCentre = _nodeCenter(tester, _TestHarness.bottom);
    final primary = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await primary.down(nodeCentre);
    await primary.moveBy(const Offset(20, 0));
    await tester.pump();

    final secondary = await tester.createGesture(kind: PointerDeviceKind.touch);
    await secondary.down(nodeCentre + const Offset(20, 20));
    await tester.pump();

    expect(controller.isCameraGated, isTrue);

    await primary.moveBy(const Offset(30, 0));
    await tester.pump();
    expect(updates.length, greaterThan(1));
    expect(
        testNodePosition(controller, _TestHarness.bottom).dx, greaterThan(130));

    await primary.up();
    expect(controller.isCameraGated, isTrue);

    await secondary.up();
    await tester.pump();
    expect(controller.isCameraGated, isFalse);

    controller.dispose();
  });

  testWidgets(
      'remaining finger after primary lift keeps camera gated until release',
      (tester) async {
    final controller = _TestHarness.newController();

    await _pumpGraph(
      tester,
      controller: controller,
      onNodeDragStart: (_, __) {},
    );

    final nodeCentre = _nodeCenter(tester, _TestHarness.bottom);
    final primary = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await primary.down(nodeCentre);
    await primary.moveBy(const Offset(20, 0));
    await tester.pump();

    final secondary = await tester.createGesture(kind: PointerDeviceKind.touch);
    await secondary.down(nodeCentre + const Offset(16, 16));
    await tester.pump();

    await primary.up();
    expect(controller.isCameraGated, isTrue);

    await secondary.up();
    await tester.pump();
    expect(controller.isCameraGated, isFalse);

    controller.dispose();
  });

  testWidgets('pointer cancel clears presentation and notifies cancel',
      (tester) async {
    final controller = _TestHarness.newController();
    Node<int>? cancelled;
    var endCount = 0;

    await _pumpGraph(
      tester,
      controller: controller,
      onNodeDragCancel: (node) => cancelled = node,
      onNodeDragEnd: (_, __) => endCount++,
    );

    final nodeCentre = _nodeCenter(tester, _TestHarness.bottom);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(nodeCentre);
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    final layoutPoint = controller.renderSnapshot.layout!.positions['3']!;
    expect(
      testNodePosition(controller, _TestHarness.bottom),
      isNot(Offset(layoutPoint.x, layoutPoint.y)),
    );

    await gesture.cancel();
    await tester.pump();

    expect(cancelled, _TestHarness.bottom);
    expect(endCount, 0);
    expect(
      testNodePosition(controller, _TestHarness.bottom),
      Offset(layoutPoint.x, layoutPoint.y),
    );

    controller.dispose();
  });

  testWidgets('topmost overlap hit follows shared paint order', (tester) async {
    final controller = _TestHarness.newController();
    Node<int>? dragged;

    await _pumpGraph(
      tester,
      controller: controller,
      layoutAlgorithm: const _OverlappingFixedLayout(),
      nodePaintOrder: const ['3', '1'],
      onNodeDragStart: (node, _) => dragged = node,
    );

    final overlap = _nodeCenter(tester, _TestHarness.bottom);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(overlap);
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();

    expect(dragged, _TestHarness.top);

    await gesture.up();
    controller.dispose();
  });

  testWidgets('topmost overlap tap follows shared paint order', (tester) async {
    final controller = _TestHarness.newController();
    Node<int>? tapped;

    await _pumpGraph(
      tester,
      controller: controller,
      layoutAlgorithm: const _OverlappingFixedLayout(),
      nodePaintOrder: const ['3', '1'],
      onNodeTap: (node) => tapped = node,
    );

    final overlap = _nodeCenter(tester, _TestHarness.bottom);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(overlap);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(tapped, _TestHarness.top);

    controller.dispose();
  });

  testWidgets(
    'node tap after camera pan uses GraphLayoutView scene localToGlobal',
    (tester) async {
      final controller = _TestHarness.newController();
      Node<int>? tapped;

      await _pumpGraph(
        tester,
        controller: controller,
        onNodeTap: (node) => tapped = node,
      );

      controller.jumpToPosition(const Offset(320, 280));
      await tester.pump();

      final scene = testNodePosition(controller, _TestHarness.bottom);
      final viewportMapped = controller.sceneToViewportLocal(scene);
      expect(
        (viewportMapped - scene).distance,
        greaterThan(40),
        reason: 'camera must be non-identity for this proof',
      );

      final box = tester.renderObject<RenderBox>(find.byType(GraphLayoutView));
      expect(
        box.globalToLocal(box.localToGlobal(viewportMapped)),
        viewportMapped,
      );
      expect(
        (box.globalToLocal(box.localToGlobal(scene)) - scene).distance,
        lessThan(0.5),
      );

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.down(box.localToGlobal(viewportMapped));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(
        tapped,
        _TestHarness.middle,
        reason: 'viewport-local mis-map hits a different node centre',
      );

      tapped = null;
      await gesture.down(box.localToGlobal(scene));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(tapped, _TestHarness.bottom);

      controller.dispose();
    },
  );

  testWidgets(
    'overlap tap after camera pan misses when scene is mis-mapped',
    (tester) async {
      final controller = _TestHarness.newController();
      Node<int>? tapped;

      await _pumpGraph(
        tester,
        controller: controller,
        layoutAlgorithm: const _OverlappingFixedLayout(),
        nodePaintOrder: const ['3', '1'],
        onNodeTap: (node) => tapped = node,
      );

      final scene = testNodePosition(controller, _TestHarness.bottom);
      controller.jumpToPosition(scene);
      await tester.pump();

      final viewportMapped = controller.sceneToViewportLocal(scene);
      expect((viewportMapped - scene).distance, greaterThan(40));

      final box = tester.renderObject<RenderBox>(find.byType(GraphLayoutView));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.down(box.localToGlobal(viewportMapped));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(
        tapped,
        isNull,
        reason: 'mis-mapped pointer must miss stacked overlap centres',
      );

      await gesture.down(box.localToGlobal(scene));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(tapped, _TestHarness.top);

      controller.dispose();
    },
  );

  testWidgets(
      'drag updates only moved node and incident edge geometry in one frame',
      (tester) async {
    final controller = _TestHarness.newController();
    final recorder = _EdgeGeometryRecorder();

    await _pumpGraph(
      tester,
      controller: controller,
      edgePainter: recorder,
      onNodeDragStart: (_, __) {},
      onNodeDragUpdate: (_, __) {},
    );

    final unrelatedBefore = recorder.snapshotFor(_TestHarness.unrelatedEdge);
    final nodeCentre = _nodeCenter(tester, _TestHarness.bottom);
    final layoutCentre = testNodePosition(controller, _TestHarness.bottom);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(nodeCentre);
    await gesture.moveBy(const Offset(35, 0));
    await tester.pump();

    final movedCentre = testNodePosition(controller, _TestHarness.bottom);
    final incident = recorder.lastFrameFor(_TestHarness.edge);
    final unrelatedAfter = recorder.snapshotFor(_TestHarness.unrelatedEdge);

    expect(movedCentre.dx, greaterThan(layoutCentre.dx));
    expect(movedCentre.dy, closeTo(layoutCentre.dy, 0.01));
    expect(incident.destination, movedCentre);
    expect(incident.source, testNodePosition(controller, _TestHarness.middle));
    expect(unrelatedAfter, unrelatedBefore);

    await gesture.up();
    controller.dispose();
  });

  testWidgets('drag moves do not trigger global relayout', (tester) async {
    final controller = _TestHarness.newController();
    final algorithm = _CountingLayoutAlgorithm();

    await _pumpGraph(
      tester,
      controller: controller,
      layoutAlgorithm: algorithm,
    );

    final relayoutsAfterSetup = controller.relayoutInvocationCount;
    final layoutCallsAfterSetup = algorithm.layoutCalls;
    final nodeCentre = _nodeCenter(tester, _TestHarness.bottom);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(nodeCentre);
    for (var i = 0; i < 5; i++) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();

    expect(controller.relayoutInvocationCount, relayoutsAfterSetup);
    expect(algorithm.layoutCalls, layoutCallsAfterSetup);

    controller.dispose();
  });

  testWidgets('nodeTapHitTester resolves tap below body without starting drag',
      (tester) async {
    final controller = _TestHarness.newController();
    Node<int>? tapped;
    Node<int>? dragStarted;

    const bottomId = '3';
    NodeTapHitTester hitTester = (scenePosition, orderedIds) {
      final centre = testNodePosition(controller, _TestHarness.bottom);
      final bodyBottom = centre.dy + _TestHarness.bottom.size / 2;
      final tapZone = Offset(centre.dx, bodyBottom + 30);
      if ((scenePosition - tapZone).distance < 1) {
        return bottomId;
      }
      return null;
    };

    await _pumpGraph(
      tester,
      controller: controller,
      onNodeTap: (node) => tapped = node,
      onNodeDragStart: (node, _) => dragStarted = node,
      nodeTapHitTester: hitTester,
    );

    final centre = testNodePosition(controller, _TestHarness.bottom);
    final bodyBottom = centre.dy + _TestHarness.bottom.size / 2;
    final tapScene = Offset(centre.dx, bodyBottom + 30);
    final tapGlobal = _globalForScene(tester, tapScene);

    final tapGesture = await tester.createGesture(kind: PointerDeviceKind.touch);
    await tapGesture.down(tapGlobal);
    await tapGesture.up();
    await tester.pump();

    expect(tapped, _TestHarness.bottom);
    expect(dragStarted, isNull);
    tapped = null;

    final viewer =
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    viewer.transformationController!.value = Matrix4.identity()
      ..translateByDouble(-100, -100, 0, 1)
      ..scaleByDouble(2, 2, 1, 1);
    await tester.pump();
    final cameraBefore = viewer.transformationController!.value.clone();
    final dragGlobal = _globalForScene(tester, tapScene);

    final dragGesture =
        await tester.createGesture(kind: PointerDeviceKind.touch);
    await dragGesture.down(dragGlobal);
    await dragGesture.moveBy(const Offset(70, 30));
    await dragGesture.moveBy(const Offset(50, 20));
    await tester.pump();

    expect(dragStarted, isNull);
    expect(viewer.transformationController!.value, isNot(cameraBefore));
    await dragGesture.up();

    controller.dispose();
  });

  testWidgets('nodeTapHitTester that returns null keeps body tap selection',
      (tester) async {
    final controller = _TestHarness.newController();
    Node<int>? tapped;

    await _pumpGraph(
      tester,
      controller: controller,
      onNodeTap: (node) => tapped = node,
      nodeTapHitTester: (_, __) => null,
    );

    final tapGesture = await tester.createGesture(kind: PointerDeviceKind.touch);
    await tapGesture.down(_nodeCenter(tester, _TestHarness.bottom));
    await tapGesture.up();
    await tester.pump();

    expect(tapped, _TestHarness.bottom);
    controller.dispose();
  });
}

class _TestHarness {
  static const top = Node<int>(data: 1, size: 100);
  static const middle = Node<int>(data: 2, size: 100);
  static const bottom = Node<int>(data: 3, size: 100);
  static const far = Node<int>(data: 4, size: 100);
  static const edge = Edge<Node<int>, int>(
    source: middle,
    destination: bottom,
    data: 1,
  );
  static const unrelatedEdge = Edge<Node<int>, int>(
    source: top,
    destination: far,
    data: 2,
  );

  static GraphController<Node<int>, Edge<Node<int>, int>> newController() =>
      testIntIntGraphController();
}

Future<void> _pumpGraph(
  WidgetTester tester, {
  required GraphController<Node<int>, Edge<Node<int>, int>> controller,
  SceneLayoutAlgorithm? layoutAlgorithm,
  EdgePainter<Node<int>, Edge<Node<int>, int>>? edgePainter,
  NodeDragStartCallback<Node<int>>? onNodeDragStart,
  NodeDragUpdateCallback<Node<int>>? onNodeDragUpdate,
  NodeDragEndCallback<Node<int>>? onNodeDragEnd,
  NodeDragCancelCallback<Node<int>>? onNodeDragCancel,
  NodeDragPositionTransform<Node<int>>? transformNodeDragPosition,
  NodeTapCallback<Node<int>>? onNodeTap,
  NodeTapHitTester? nodeTapHitTester,
  List<GraphNodeId>? nodePaintOrder,
}) async {
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: SizedBox(
        width: 800,
        height: 600,
        child: GraphView<Node<int>, Edge<Node<int>, int>>(
          controller: controller,
          canvasSize: const GraphCanvasSize.fixed(Size(500, 500)),
          layoutAlgorithm: layoutAlgorithm ?? const _FixedLayout(),
          edgePainter: edgePainter ?? const LineEdgePainter(),
          nodePaintOrder: nodePaintOrder,
          onNodeDragStart: onNodeDragStart,
          onNodeDragUpdate: onNodeDragUpdate,
          onNodeDragEnd: onNodeDragEnd,
          onNodeDragCancel: onNodeDragCancel,
          transformNodeDragPosition: transformNodeDragPosition,
          onNodeTap: onNodeTap,
          nodeTapHitTester: nodeTapHitTester,
          nodeBuilder: (context, node) => SizedBox(
            width: node.size,
            height: node.size,
            child: Text('${node.data}'),
          ),
        ),
      ),
    ),
  );

  controller.reconcileTopology(
    {
      _TestHarness.top,
      _TestHarness.middle,
      _TestHarness.bottom,
      _TestHarness.far,
    },
    {_TestHarness.edge, _TestHarness.unrelatedEdge},
  );
  await tester.pumpAndSettle();
}

Offset _nodeCenter(WidgetTester tester, Node<int> node) => _globalForScene(
      tester,
      testNodePosition(_controllerFromTester(tester), node),
    );

GraphController<Node<int>, Edge<Node<int>, int>> _controllerFromTester(
  WidgetTester tester,
) {
  final element =
      tester.element(find.byType(GraphView<Node<int>, Edge<Node<int>, int>>));
  final state = element as StatefulElement;
  final graphView = state.widget as GraphView<Node<int>, Edge<Node<int>, int>>;
  return graphView.controller;
}

Offset _globalForScene(WidgetTester tester, Offset scene) {
  final box = tester.renderObject<RenderBox>(find.byType(GraphLayoutView));
  return box.localToGlobal(scene);
}

final class _OverlappingFixedLayout implements SceneLayoutAlgorithm {
  const _OverlappingFixedLayout();

  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) async* {
    yield GraphLayoutFrame(
      ticket: request.ticket,
      sequence: 0,
      positions: _FixedLayout.positionsFor(
        request.nodeIds,
        overlapTopAndBottom: true,
      ),
      isTerminal: true,
    );
  }
}

final class _FixedLayout implements SceneLayoutAlgorithm {
  const _FixedLayout();

  static Map<GraphNodeId, ScenePoint> positionsFor(
    Set<GraphNodeId> ids, {
    bool overlapTopAndBottom = false,
  }) {
    final positions = <GraphNodeId, ScenePoint>{};
    if (ids.contains('1')) {
      positions['1'] = overlapTopAndBottom
          ? ScenePoint(x: 150, y: 250)
          : ScenePoint(x: 150, y: 150);
    }
    if (ids.contains('2')) {
      positions['2'] = ScenePoint(x: 250, y: 250);
    }
    if (ids.contains('3')) {
      positions['3'] = ScenePoint(x: 150, y: 250);
    }
    if (ids.contains('4')) {
      positions['4'] = ScenePoint(x: 400, y: 400);
    }
    return positions;
  }

  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) async* {
    yield GraphLayoutFrame(
      ticket: request.ticket,
      sequence: 0,
      positions: positionsFor(request.nodeIds),
      isTerminal: true,
    );
  }
}

final class _CountingLayoutAlgorithm implements SceneLayoutAlgorithm {
  var layoutCalls = 0;

  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) async* {
    layoutCalls++;
    yield GraphLayoutFrame(
      ticket: request.ticket,
      sequence: 0,
      positions: _FixedLayout.positionsFor(request.nodeIds),
      isTerminal: true,
    );
  }
}

final class _EdgeGeometryRecorder
    implements EdgePainter<Node<int>, Edge<Node<int>, int>> {
  _EdgeGeometryRecorder();

  final _frames = <Edge<Node<int>, int>, _EdgeFrame>{};

  _EdgeFrame snapshotFor(Edge<Node<int>, int> edge) =>
      _frames[edge] ?? _EdgeFrame.zero;

  _EdgeFrame lastFrameFor(Edge<Node<int>, int> edge) => _frames[edge]!;

  @override
  void paint(
    Canvas canvas,
    Edge<Node<int>, int> edge,
    Offset sourcePosition,
    Offset destinationPosition,
  ) {
    _frames[edge] = _EdgeFrame(
      source: sourcePosition,
      destination: destinationPosition,
    );
  }
}

final class _EdgeFrame {
  const _EdgeFrame({
    required this.source,
    required this.destination,
  });

  static const zero = _EdgeFrame(
    source: Offset.zero,
    destination: Offset.zero,
  );

  final Offset source;
  final Offset destination;

  @override
  bool operator ==(Object other) =>
      other is _EdgeFrame &&
      other.source == source &&
      other.destination == destination;

  @override
  int get hashCode => Object.hash(source, destination);
}
