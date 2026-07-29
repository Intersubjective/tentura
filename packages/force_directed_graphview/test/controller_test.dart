import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

void main() {
  late GraphController controller;

  setUp(() {
    controller = GraphController();
  });

  test('GraphController is empty by default', () {
    expect(controller.nodes, isEmpty);
    expect(controller.edges, isEmpty);
  });

  const node1 = Node(data: 1, size: 100);
  const node2 = Node(data: 2, size: 200);
  const edge12 = Edge(source: node1, destination: node2, data: 10);

  test('Add and remove node', () {
    controller.mutate((mutator) => mutator.addNode(node1));
    expect(controller.nodes.contains(node1), true);

    controller.mutate((mutator) => mutator.removeNode(node1));
    expect(controller.nodes.contains(node1), false);
  });

  test('Add and remove edge', () {
    controller.mutate((mutator) {
      mutator
        ..addNode(node1)
        ..addNode(node2)
        ..addEdge(edge12);
    });

    expect(controller.edges.contains(edge12), true);

    controller.mutate((mutator) => mutator.removeEdge(edge12));
    expect(controller.edges.contains(edge12), false);
  });

  test('Throws when adding existing node', () {
    controller.mutate((mutator) => mutator.addNode(node1));

    expect(
      () => controller.mutate((mutator) => mutator.addNode(node1)),
      throwsA(isInstanceOf<StateError>()),
    );
  });

  test('Throws when removing non-existing node', () {
    expect(
      () => controller.mutate((mutator) => mutator.removeNode(node1)),
      throwsA(isInstanceOf<StateError>()),
    );
  });

  test('Throws when adding edge with non-existing node', () {
    controller.mutate((mutator) => mutator.addNode(node1));

    expect(
      () => controller.mutate((mutator) => mutator.addEdge(edge12)),
      throwsA(isInstanceOf<StateError>()),
    );
  });

  test('Throws when removing non-existing edge', () {
    expect(
      () => controller.mutate((mutator) => mutator.removeEdge(edge12)),
      throwsA(isInstanceOf<StateError>()),
    );
  });

  testWidgets('fitToNodes on a laid-out graph does not throw', (tester) async {
    final graphController =
        GraphController<Node<int>, Edge<Node<int>, void>>();
    const near = Node<int>(data: 1, size: 50);
    const far = Node<int>(data: 2, size: 50);

    await tester.pumpWidget(
      MaterialApp(
        home: GraphView<Node<int>, Edge<Node<int>, void>>(
          controller: graphController,
          canvasSize: const GraphCanvasSize.fixed(Size(500, 500)),
          layoutAlgorithm: const FruchtermanReingoldAlgorithm(iterations: 1),
          nodeBuilder: (context, node) => const SizedBox.shrink(),
        ),
      ),
    );

    graphController.mutate((m) {
      m
        ..addNode(near)
        ..addNode(far);
    });
    await tester.pumpAndSettle();

    expect(() => graphController.fitToNodes([near, far]), returnsNormally);
    expect(() => graphController.fitToNodes([]), returnsNormally);

    graphController.dispose();
  });

  testWidgets('clear resets layout and allows relayout after mutate',
      (tester) async {
    final graphController =
        GraphController<Node<int>, Edge<Node<int>, void>>();
    const node = Node<int>(data: 1, size: 50);

    await tester.pumpWidget(
      MaterialApp(
        home: GraphView<Node<int>, Edge<Node<int>, void>>(
          controller: graphController,
          canvasSize: const GraphCanvasSize.fixed(Size(500, 500)),
          layoutAlgorithm: const FruchtermanReingoldAlgorithm(iterations: 1),
          nodeBuilder: (context, node) => const SizedBox.shrink(),
        ),
      ),
    );

    graphController.mutate((m) => m..addNode(node));
    await tester.pumpAndSettle();
    expect(graphController.canLayout, isTrue);

    graphController.clear();
    expect(graphController.canLayout, isFalse);

    graphController.mutate((m) => m..addNode(node));
    await tester.pumpAndSettle();
    expect(graphController.canLayout, isTrue);

    graphController.dispose();
  });
}
