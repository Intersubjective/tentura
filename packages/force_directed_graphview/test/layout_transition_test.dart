import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

void main() {
  testWidgets('graph interpolates towards a newly computed layout',
      (tester) async {
    final controller = GraphController<Node<String>, Edge<Node<String>, void>>();
    const a = Node<String>(data: 'a', size: 10);
    const b = Node<String>(data: 'b', size: 10);

    await tester.pumpWidget(
      MaterialApp(
        home: GraphView<Node<String>, Edge<Node<String>, void>>(
          controller: controller,
          canvasSize: const GraphCanvasSize.fixed(Size(500, 500)),
          layoutAlgorithm: const FruchtermanReingoldAlgorithm(iterations: 1),
          layoutTransitionDuration: const Duration(milliseconds: 300),
          nodeBuilder: (context, node) => const SizedBox.shrink(),
        ),
      ),
    );

    controller.mutate((m) => m..addNode(a));
    await tester.pumpAndSettle();
    final first = controller.layout.getPosition(a);

    controller.mutate((m) => m..addNode(b));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(controller.isLayoutSettling, isTrue);
    expect(controller.isLayoutTransitioning, isTrue);

    // Mid-transition the graph must be laid out and must not have snapped.
    expect(controller.canLayout, isTrue);
    expect(controller.layout.hasPosition(a), isTrue);

    await tester.pumpAndSettle();
    expect(controller.isLayoutSettling, isFalse);
    expect(controller.isLayoutTransitioning, isFalse);
    expect(controller.layout.hasPosition(b), isTrue);
    expect(first, isNotNull);

    controller.dispose();
  });
}
