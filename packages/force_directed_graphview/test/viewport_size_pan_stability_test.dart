import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'support/fixed_scene_layout.dart';
import 'support/int_graph_controller.dart';
import 'support/settle_graph_layout.dart';

void main() {
  // tentura-s7gl.99: the viewport size was rebuilt from the scene-space quad
  // (width × scale) and changed in its last bit as a pan moved the camera, so
  // everything keyed on it was recomputed on a plain pan.
  testWidgets(
    'viewportSize is the view layout size and stays fixed while panning',
    (tester) async {
      const viewport = Size(1200, 743);
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = testIntIntGraphController();
      addTearDown(controller.dispose);
      const node = Node<int>(data: 1, size: 40);
      await tester.pumpWidget(
        MaterialApp(
          home: GraphView<Node<int>, Edge<Node<int>, int>>(
            controller: controller,
            canvasSize: const GraphCanvasSize.fixed(Size(6000, 6000)),
            layoutAlgorithm: FixedSceneLayoutAlgorithm({
              '1': ScenePoint(x: 3000, y: 3000),
            }),
            edgePainter: const LineEdgePainter(),
            nodeBuilder: (context, node) =>
                SizedBox(width: node.size, height: node.size),
          ),
        ),
      );
      controller.reconcileTopology({node}, {});
      await settleGraphLayout(tester, controller);
      await tester.pumpAndSettle();
      // A fractional camera origin: from here the pan below crosses values
      // where (left + width) - left is not exactly width in doubles.
      controller.jumpToPosition(const Offset(1500.3, 1500.3));
      await tester.pump();

      final camera = tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!;
      final seen = <Size>{controller.viewportSize!};
      for (var i = 0; i < 120; i++) {
        camera.value = camera.value.clone()
          ..setTranslationRaw(
            camera.value.storage[12] + 4,
            camera.value.storage[13] + 2,
            camera.value.storage[14],
          );
        await tester.pump(const Duration(milliseconds: 16));
        seen.add(controller.viewportSize!);
      }

      expect(seen, {viewport});
    },
  );
}
