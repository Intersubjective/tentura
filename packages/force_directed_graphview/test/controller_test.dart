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
        testIntGraphController();
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
        testIntGraphController();
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
            layoutAlgorithm: const _CornerFixedSceneLayout(),
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
        testIntGraphController();
    const near = Node<int>(data: 1, size: 50);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: viewportW,
          height: viewportH,
          child: GraphView<Node<int>, Edge<Node<int>, void>>(
            controller: graphController,
            canvasSize: const GraphCanvasSize.fixed(Size(500, 500)),
            layoutAlgorithm: const _CornerFixedSceneLayout(),
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
        testIntGraphController();
    const near = Node<int>(data: 1, size: 50);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: viewportW,
          height: viewportH,
          child: GraphView<Node<int>, Edge<Node<int>, void>>(
            controller: graphController,
            canvasSize: const GraphCanvasSize.fixed(Size(500, 500)),
            layoutAlgorithm: const _CornerFixedSceneLayout(),
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
      final position = graphController.getPosition(near);
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
        testIntGraphController();
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

final class _CornerFixedSceneLayout implements SceneLayoutAlgorithm {
  const _CornerFixedSceneLayout();

  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) async* {
    final ids = request.nodeIds.toList()..sort();
    final positions = <GraphNodeId, ScenePoint>{};
    if (ids.isNotEmpty) {
      positions[ids[0]] = ScenePoint(x: 100, y: 100);
    }
    if (ids.length > 1) {
      positions[ids[1]] = ScenePoint(x: 3900, y: 3900);
    }
    yield GraphLayoutFrame(
      ticket: request.ticket,
      sequence: 0,
      positions: positions,
      isTerminal: true,
    );
  }
}
