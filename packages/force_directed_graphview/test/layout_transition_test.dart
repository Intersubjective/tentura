import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'support/int_graph_controller.dart';

void main() {
  testWidgets('graph interpolates towards a newly computed layout',
      (tester) async {
    final controller = testIntGraphController();
    const a = Node<int>(data: 1, size: 10);
    const b = Node<int>(data: 2, size: 10);

    await tester.pumpWidget(
      MaterialApp(
        home: GraphView<Node<int>, Edge<Node<int>, void>>(
          controller: controller,
          canvasSize: const GraphCanvasSize.fixed(Size(500, 500)),
          layoutAlgorithm: const FruchtermanReingoldSceneLayoutAlgorithm(
            iterations: 1,
          ),
          layoutTransitionDuration: const Duration(milliseconds: 300),
          nodeBuilder: (context, node) => const SizedBox.shrink(),
        ),
      ),
    );

    testAddNode(controller, a);
    await tester.pumpAndSettle();
    final first = testNodePosition(controller, a);

    testAddNode(controller, b);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(controller.isLayoutSettling, isTrue);
    expect(controller.isLayoutTransitioning, isTrue);

    expect(controller.canLayout, isTrue);
    expect(
      controller.getPositionOrNullForId(testIntNodeId(a)),
      isNotNull,
    );

    await tester.pumpAndSettle();
    expect(controller.isLayoutSettling, isFalse);
    expect(controller.isLayoutTransitioning, isFalse);
    expect(
      controller.getPositionOrNullForId(testIntNodeId(b)),
      isNotNull,
    );
    expect(first, isNotNull);

    controller.dispose();
  });
}
