import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'support/fixed_scene_layout.dart';
import 'support/int_graph_controller.dart';
import 'support/settle_graph_layout.dart';

void main() {
  for (final nodeCallbacks in [false, true]) {
    for (final gestureKind in ['tap', 'secondary', 'long press']) {
      testWidgets(
          '$gestureKind routes empty canvas with node hooks $nodeCallbacks',
          (tester) async {
        final controller = testIntGraphController();
        const node = Node(data: 1, size: 40);
        testAddNode(controller, node);
        final taps = <Offset>[];
        final secondary = <Offset>[];
        final holds = <Offset>[];
        final nodeTaps = <Node<int>>[];
        await tester.pumpWidget(
          MaterialApp(
            home: GraphView<Node<int>, Edge<Node<int>, void>>(
              controller: controller,
              canvasSize: const GraphCanvasSize.fixed(Size(800, 600)),
              layoutAlgorithm: FixedSceneLayoutAlgorithm({
                '1': ScenePoint(x: 0, y: 0),
              }),
              nodeBuilder: (_, node) => SizedBox.square(dimension: node.size),
              onNodeTap: nodeCallbacks ? nodeTaps.add : null,
              onCanvasTap: taps.add,
              onCanvasSecondaryTap: secondary.add,
              onCanvasLongPress: holds.add,
            ),
          ),
        );
        await settleGraphLayout(tester, controller);
        final viewer =
            tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
        viewer.transformationController!.value = Matrix4.identity()
          ..translateByDouble(100, 50, 0, 1)
          ..scaleByDouble(2, 2, 1, 1);
        await tester.pump();
        final origin = tester.getTopLeft(find.byType(InteractiveViewer));
        Future<void> press(Offset viewport) async {
          final gesture = await tester.createGesture(
            kind: gestureKind == 'secondary'
                ? PointerDeviceKind.mouse
                : PointerDeviceKind.touch,
            buttons: gestureKind == 'secondary'
                ? kSecondaryMouseButton
                : kPrimaryButton,
          );
          await gesture.down(origin + viewport);
          if (gestureKind == 'long press') {
            await tester
                .pump(kLongPressTimeout + const Duration(milliseconds: 1));
          }
          await gesture.up();
          await tester.pump();
        }

        await press(const Offset(300, 250));
        final expected = gestureKind == 'tap'
            ? taps
            : gestureKind == 'secondary'
                ? secondary
                : holds;
        expect(expected, hasLength(1));
        expect(expected.single.dx, closeTo(100, 1));
        expect(expected.single.dy, closeTo(100, 1));
        expect(taps.length + secondary.length + holds.length, 1);
        await press(const Offset(100, 50));
        expect(taps.length + secondary.length + holds.length, 1);
        if (nodeCallbacks && gestureKind == 'tap') expect(nodeTaps, [node]);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      });
    }
  }

  testWidgets('empty canvas pan cancels tap and long press', (tester) async {
    final controller = testIntGraphController();
    testAddNode(controller, const Node(data: 1, size: 40));
    final calls = <Offset>[];
    await tester.pumpWidget(
      MaterialApp(
        home: GraphView<Node<int>, Edge<Node<int>, void>>(
          controller: controller,
          canvasSize: const GraphCanvasSize.fixed(Size(800, 600)),
          layoutAlgorithm:
              FixedSceneLayoutAlgorithm({'1': ScenePoint(x: 0, y: 0)}),
          nodeBuilder: (_, node) => SizedBox.square(dimension: node.size),
          onCanvasTap: calls.add,
          onCanvasSecondaryTap: calls.add,
          onCanvasLongPress: calls.add,
        ),
      ),
    );
    await settleGraphLayout(tester, controller);
    final viewer =
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    viewer.transformationController!.value = Matrix4.identity()
      ..translateByDouble(-100, -100, 0, 1)
      ..scaleByDouble(2, 2, 1, 1);
    await tester.pump();
    final before = viewer.transformationController!.value.clone();
    final gesture = await tester.startGesture(const Offset(300, 250));
    await gesture.moveBy(const Offset(60, 40));
    await gesture.moveBy(const Offset(40, 20));
    await tester.pump(kLongPressTimeout);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expect(viewer.transformationController!.value, isNot(before));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
