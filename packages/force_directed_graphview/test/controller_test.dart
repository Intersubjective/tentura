import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'support/int_graph_controller.dart';

void main() {
  late GraphController<Node<int>, Edge<Node<int>, int>> controller;

  setUp(() {
    controller = testIntIntGraphController();
  });

  test('GraphController is empty by default', () {
    expect(controller.nodes, isEmpty);
    expect(controller.edges, isEmpty);
  });

  const node1 = Node(data: 1, size: 100);
  const node2 = Node(data: 2, size: 200);
  const edge12 = Edge(source: node1, destination: node2, data: 10);

  test('Add and remove node', () {
    testAddNode(controller, node1);
    expect(controller.nodes.contains(node1), true);

    testRemoveNode(controller, node1);
    expect(controller.nodes.contains(node1), false);
  });

  test('Add and remove edge', () {
    testAddNode(controller, node1);
    testAddNode(controller, node2);
    testAddEdge(controller, edge12);

    expect(controller.edges.contains(edge12), true);

    testRemoveEdge(controller, edge12);
    expect(controller.edges.contains(edge12), false);
  });

  test('reconcileTopology replaces payload for the same id', () {
    testAddNode(controller, node1);
    const updated = Node<int>(data: 1, size: 150);
    controller.reconcileTopology({updated}, controller.edges);
    expect(controller.nodes.single.size, 150);
  });

  testWidgets('fitToNodeIds on a laid-out graph does not throw', (tester) async {
    final graphController = testIntGraphController();
    const near = Node<int>(data: 1, size: 50);
    const far = Node<int>(data: 2, size: 50);

    await tester.pumpWidget(
      MaterialApp(
        home: GraphView<Node<int>, Edge<Node<int>, void>>(
          controller: graphController,
          canvasSize: const GraphCanvasSize.fixed(Size(500, 500)),
          layoutAlgorithm: const FruchtermanReingoldSceneLayoutAlgorithm(
            iterations: 1,
          ),
          nodeBuilder: (context, node) => const SizedBox.shrink(),
        ),
      ),
    );

    testAddNode(graphController, near);
    testAddNode(graphController, far);
    await tester.pumpAndSettle();

    expect(
      () => graphController.fitToNodeIds([
        testIntNodeId(near),
        testIntNodeId(far),
      ]),
      returnsNormally,
    );
    expect(() => graphController.fitToNodeIds(const []), returnsNormally);

    graphController.dispose();
  });

  testWidgets('fitToNodeIds respects InteractiveViewer boundary scale floor',
      (tester) async {
    const canvasSide = 4096.0;
    const widgetMinScale = 0.1;
    const viewportW = 1600.0;
    const viewportH = 900.0;
    final expectedFloor = math.max(
      widgetMinScale,
      math.max(viewportW / canvasSide, viewportH / canvasSide),
    );

    final graphController = testIntGraphController();
    const near = Node<int>(data: 1, size: 50);
    const far = Node<int>(data: 2, size: 50);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: viewportW,
          height: viewportH,
          child: GraphView<Node<int>, Edge<Node<int>, void>>(
            controller: graphController,
            minScale: widgetMinScale,
            canvasSize: GraphCanvasSize.fixed(
              const Size(canvasSide, canvasSide),
            ),
            layoutAlgorithm: const _CornerFixedSceneLayout(),
            nodeBuilder: (context, node) => const SizedBox.shrink(),
          ),
        ),
      ),
    );

    testAddNode(graphController, near);
    testAddNode(graphController, far);
    await tester.pumpAndSettle();

    graphController.fitToNodeIds([
      testIntNodeId(near),
      testIntNodeId(far),
    ]);
    await tester.pump();

    expect(graphController.currentScale, greaterThanOrEqualTo(expectedFloor));

    graphController.dispose();
  });

  testWidgets('jumpToNodeId with resetScale restores unit scale', (tester) async {
    final graphController = testIntGraphController();
    const near = Node<int>(data: 1, size: 50);

    await tester.pumpWidget(
      MaterialApp(
        home: GraphView<Node<int>, Edge<Node<int>, void>>(
          controller: graphController,
          canvasSize: const GraphCanvasSize.fixed(Size(500, 500)),
          layoutAlgorithm: const _CornerFixedSceneLayout(),
          nodeBuilder: (context, node) => const SizedBox.shrink(),
        ),
      ),
    );

    testAddNode(graphController, near);
    await tester.pumpAndSettle();

    graphController.zoomIn(2);
    await tester.pump();

    graphController.jumpToNodeId(testIntNodeId(near), resetScale: true);
    await tester.pump();

    expect(graphController.currentScale, closeTo(1.0, 0.01));

    graphController.dispose();
  });

  testWidgets('jumpToNodeId centers after zoom and pan', (tester) async {
    final graphController = testIntGraphController();
    const near = Node<int>(data: 1, size: 50);

    await tester.pumpWidget(
      MaterialApp(
        home: GraphView<Node<int>, Edge<Node<int>, void>>(
          controller: graphController,
          canvasSize: const GraphCanvasSize.fixed(Size(500, 500)),
          layoutAlgorithm: const _CornerFixedSceneLayout(),
          nodeBuilder: (context, node) => const SizedBox.shrink(),
        ),
      ),
    );

    testAddNode(graphController, near);
    await tester.pumpAndSettle();

    graphController.zoomIn(2);
    await tester.pump();

    final position = testNodePosition(graphController, near);
    graphController.jumpToPosition(position + const Offset(100, 50));
    await tester.pump();

    graphController.jumpToNodeId(testIntNodeId(near));
    await tester.pump();

    final after = testNodePosition(graphController, near);
    expect(after.dx, closeTo(position.dx, 1));
    expect(after.dy, closeTo(position.dy, 1));

    graphController.jumpToNodeId(testIntNodeId(near), resetScale: true);
    await tester.pump();
    expect(graphController.currentScale, closeTo(1.0, 0.01));

    graphController.dispose();
  });

  testWidgets('clear resets layout and allows relayout after reconcileTopology',
      (tester) async {
    final graphController = testIntGraphController();
    const node = Node<int>(data: 1, size: 50);

    await tester.pumpWidget(
      MaterialApp(
        home: GraphView<Node<int>, Edge<Node<int>, void>>(
          controller: graphController,
          canvasSize: const GraphCanvasSize.fixed(Size(500, 500)),
          layoutAlgorithm: const FruchtermanReingoldSceneLayoutAlgorithm(
            iterations: 1,
          ),
          nodeBuilder: (context, node) => const SizedBox.shrink(),
        ),
      ),
    );

    testAddNode(graphController, node);
    await tester.pumpAndSettle();
    expect(graphController.canLayout, isTrue);

    graphController.clear();
    expect(graphController.nodes, isEmpty);

    testAddNode(graphController, node);
    await tester.pumpAndSettle();
    expect(graphController.canLayout, isTrue);

    graphController.dispose();
  });
}

final class _CornerFixedSceneLayout implements SceneLayoutAlgorithm {
  const _CornerFixedSceneLayout();

  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) async* {
    final positions = <GraphNodeId, ScenePoint>{};
    var i = 0;
    for (final id in request.nodesById.keys) {
      positions[id] = ScenePoint(x: 50.0 * i, y: 50.0 * i);
      i++;
    }
    yield GraphLayoutFrame(
      ticket: request.ticket,
      sequence: 0,
      positions: positions,
      isTerminal: true,
    );
  }
}
