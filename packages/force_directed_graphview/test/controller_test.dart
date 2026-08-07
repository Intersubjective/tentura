import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

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

  testWidgets('fitToNodes respects InteractiveViewer boundary scale floor',
      (tester) async {
    const canvasSide = 4096.0;
    const widgetMinScale = 0.1;
    const viewportW = 1600.0;
    const viewportH = 900.0;
    final expectedFloor = math.max(
      widgetMinScale,
      math.max(viewportW / canvasSide, viewportH / canvasSide),
    );

    tester.view.physicalSize = const Size(viewportW, viewportH);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final graphController =
        GraphController<Node<int>, Edge<Node<int>, void>>();
    const near = Node<int>(data: 1, size: 50);
    const far = Node<int>(data: 2, size: 50);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: viewportW,
          height: viewportH,
          child: GraphView<Node<int>, Edge<Node<int>, void>>(
            controller: graphController,
            canvasSize: const GraphCanvasSize.fixed(
              Size(canvasSide, canvasSide),
            ),
            minScale: widgetMinScale,
            maxScale: 3,
            layoutAlgorithm: const _CornerFixedLayout(),
            nodeBuilder: (context, node) => const SizedBox.shrink(),
          ),
        ),
      ),
    );

    graphController.mutate((m) {
      m
        ..addNode(near)
        ..addNode(far);
    });
    await tester.pumpAndSettle();

    graphController.fitToNodes([near, far]);

    expect(
      graphController.currentScale,
      greaterThanOrEqualTo(expectedFloor - 0.01),
    );

    final scaleAtFloor = graphController.currentScale;
    graphController.zoomBy(0.5);
    expect(graphController.currentScale, closeTo(scaleAtFloor, 0.001));

    graphController.dispose();
  });

  testWidgets('jumpToNode with resetScale restores unit scale', (tester) async {
    const viewportW = 800.0;
    const viewportH = 600.0;

    tester.view.physicalSize = const Size(viewportW, viewportH);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final graphController =
        GraphController<Node<int>, Edge<Node<int>, void>>();
    const near = Node<int>(data: 1, size: 50);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: viewportW,
          height: viewportH,
          child: GraphView<Node<int>, Edge<Node<int>, void>>(
            controller: graphController,
            canvasSize: const GraphCanvasSize.fixed(Size(500, 500)),
            layoutAlgorithm: const _CornerFixedLayout(),
            nodeBuilder: (context, node) => const SizedBox.shrink(),
          ),
        ),
      ),
    );

    graphController.mutate((m) => m..addNode(near));
    await tester.pumpAndSettle();

    graphController.zoomBy(2.0);
    expect(graphController.currentScale, greaterThan(1.5));

    await graphController.jumpToNode(near, resetScale: true);
    expect(graphController.currentScale, closeTo(1.0, 0.001));

    graphController.dispose();
  });

  testWidgets('jumpToNode centers after zoom and pan', (tester) async {
    const viewportW = 800.0;
    const viewportH = 600.0;

    tester.view.physicalSize = const Size(viewportW, viewportH);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final graphController =
        GraphController<Node<int>, Edge<Node<int>, void>>();
    const near = Node<int>(data: 1, size: 50);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: viewportW,
          height: viewportH,
          child: GraphView<Node<int>, Edge<Node<int>, void>>(
            controller: graphController,
            canvasSize: const GraphCanvasSize.fixed(Size(500, 500)),
            layoutAlgorithm: const _CornerFixedLayout(),
            nodeBuilder: (context, node) => const SizedBox.shrink(),
          ),
        ),
      ),
    );

    graphController.mutate((m) => m..addNode(near));
    await tester.pumpAndSettle();

    Offset nodeScreen() {
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      final matrix = viewer.transformationController!.value;
      final position = graphController.layout.getPosition(near);
      return MatrixUtils.transformPoint(matrix, position);
    }

    graphController.zoomBy(2.0);
    await tester.pump();

    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final tc = viewer.transformationController!;
    tc.value = Matrix4.copy(tc.value)..translate(80.0, -60.0);
    await tester.pump();

    await graphController.jumpToNode(near);
    await tester.pump();
    final keepScale = nodeScreen();
    expect(keepScale.dx, closeTo(viewportW / 2, 1));
    expect(keepScale.dy, closeTo(viewportH / 2, 1));
    expect(graphController.currentScale, greaterThan(1.5));

    graphController.zoomBy(2.0);
    tc.value = Matrix4.copy(tc.value)..translate(80.0, -60.0);
    await tester.pump();

    await graphController.jumpToNode(near, resetScale: true);
    await tester.pump();
    final resetScale = nodeScreen();
    expect(resetScale.dx, closeTo(viewportW / 2, 1));
    expect(resetScale.dy, closeTo(viewportH / 2, 1));
    expect(graphController.currentScale, closeTo(1.0, 0.001));

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

final class _CornerFixedLayout implements GraphLayoutAlgorithm {
  const _CornerFixedLayout();

  static GraphLayout _layout(Set<NodeBase> nodes) {
    final builder = GraphLayoutBuilder(nodes: {...nodes});
    final nodeList = nodes.toList();
    if (nodeList.isNotEmpty) {
      builder.setNodePosition(nodeList[0], const Offset(100, 100));
    }
    if (nodeList.length > 1) {
      builder.setNodePosition(nodeList[1], const Offset(3900, 3900));
    }
    return builder.build();
  }

  @override
  Stream<GraphLayout> layout({
    required Set<NodeBase> nodes,
    required Set<EdgeBase> edges,
    required Size size,
  }) =>
      Stream.value(_layout(nodes));

  @override
  Stream<GraphLayout> relayout({
    required GraphLayout existingLayout,
    required Set<NodeBase> nodes,
    required Set<EdgeBase> edges,
    required Size size,
  }) =>
      Stream.value(_layout(nodes));
}
