import 'dart:ui' show Offset;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'support/fixed_scene_layout.dart';
import 'support/int_graph_controller.dart';
import 'support/settle_graph_layout.dart';

void main() {
  for (final ending in ['release', 'pointer cancel']) {
    testWidgets(
      'a canvas hold naming a node that is not on the graph ends with '
      '$ending: the app is told the grab failed and no node drag is reported',
      (tester) async {
        final controller = testIntGraphController();
        testAddNode(controller, const Node(data: 1, size: 40));
        addTearDown(controller.dispose);
        final failed = <GraphNodeId>[];
        final drags = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            home: GraphView<Node<int>, Edge<Node<int>, void>>(
              controller: controller,
              canvasSize: const GraphCanvasSize.fixed(Size(800, 600)),
              layoutAlgorithm: FixedSceneLayoutAlgorithm({
                '1': ScenePoint(x: 0, y: 0),
              }),
              nodeBuilder: (_, node) => SizedBox.square(dimension: node.size),
              onCanvasLongPressDrag: (_) => 'missing',
              onCanvasLongPressDragFailed: failed.add,
              onNodeDragStart: (node, _) => drags.add('start'),
              onNodeDragEnd: (node, _, __) => drags.add('end'),
              onNodeDragCancel: (node) => drags.add('cancel'),
            ),
          ),
        );
        await settleGraphLayout(tester, controller);

        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.touch,
        );
        await gesture.down(const Offset(400, 300));
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 1));
        expect(failed, ['missing'], reason: 'the lift failed at the hold');
        if (ending == 'release') {
          await gesture.up();
        } else {
          await gesture.cancel();
        }
        await tester.pump();

        expect(failed, ['missing'], reason: 'told exactly once');
        expect(drags, isEmpty, reason: 'no node drag was ever captured');
        expect(controller.isCameraGated, isFalse);
      },
    );
  }
}
