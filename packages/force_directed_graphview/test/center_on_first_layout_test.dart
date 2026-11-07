import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'support/fixed_scene_layout.dart';
import 'support/int_graph_controller.dart';
import 'support/settle_graph_layout.dart';

const _viewport = Size(400, 400);
const _canvas = Size(800, 800);

Future<GraphController<Node<int>, Edge<Node<int>, int>>> _pumpGraph(
  WidgetTester tester, {
  required bool centerOnFirstLayout,
  required GraphController<Node<int>, Edge<Node<int>, int>> controller,
}) async {
  tester.view.physicalSize = _viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: GraphView<Node<int>, Edge<Node<int>, int>>(
        controller: controller,
        canvasSize: const GraphCanvasSize.fixed(_canvas),
        centerOnFirstLayout: centerOnFirstLayout,
        layoutAlgorithm: FixedSceneLayoutAlgorithm({
          '1': ScenePoint(x: 100, y: 200),
        }),
        nodeBuilder: (context, node) =>
            SizedBox(width: node.size, height: node.size),
      ),
    ),
  );
  await tester.pump();
  return controller;
}

void main() {
  testWidgets('centerOnFirstLayout true jumps to canvas centre at scale 1', (
    tester,
  ) async {
    final controller = testIntIntGraphController();
    addTearDown(controller.dispose);
    await _pumpGraph(tester, centerOnFirstLayout: true, controller: controller);

    const node = Node<int>(data: 1, size: 40);
    controller.reconcileTopology({node}, {});
    await settleGraphLayout(tester, controller);
    await tester.pump();

    expect(controller.cameraScale, closeTo(1.0, 0.001));
    final canvasCentre = Offset(_canvas.width / 2, _canvas.height / 2);
    final viewport = controller.sceneToViewportLocal(canvasCentre);
    final pixel = controller.viewportSize!;
    expect(viewport.dx, closeTo(pixel.width / 2, 8));
    expect(viewport.dy, closeTo(pixel.height / 2, 8));
  });

  testWidgets(
    'centerOnFirstLayout false leaves the camera off the centred layout',
    (tester) async {
      final controller = testIntIntGraphController();
      addTearDown(controller.dispose);
      await _pumpGraph(
        tester,
        centerOnFirstLayout: false,
        controller: controller,
      );

      const node = Node<int>(data: 1, size: 40);
      controller.reconcileTopology({node}, {});
      await settleGraphLayout(tester, controller);
      await tester.pump();

      final point = controller.renderSnapshot.resolvePosition('1')!;
      final viewport = controller.sceneToViewportLocal(
        Offset(point.x, point.y),
      );
      final pixel = controller.viewportSize!;
      final delta = (viewport - pixel.center(Offset.zero)).distance;
      expect(delta, greaterThan(40));
    },
  );
}
