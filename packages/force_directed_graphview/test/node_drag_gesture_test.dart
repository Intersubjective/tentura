import 'dart:ui' show Offset;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:force_directed_graphview/src/widget/graph_layout_view.dart';
import 'support/int_graph_controller.dart';

void main() {
  const viewportSize = Size(800, 600);
  const canvasSize = Size(500, 500);

  test('orderedNodes respects optional paint order', () {
    final controller = testIntGraphController();
    const a = Node<int>(data: 1, size: 10);
    const b = Node<int>(data: 2, size: 10);
    const c = Node<int>(data: 3, size: 10);

    final ordered = controller
        .orderedNodes(
          {a, b, c},
          paintOrder: const [c, a],
        )
        .toList();

    expect(ordered, [c, a, b]);
  });

  testWidgets('pan and zoom without node capture', (tester) async {
    final controller = _TestHarness.newController();
    var dragUpdates = 0;

    await _pumpGraph(
      tester,
      controller: controller,
      onNodeDragUpdate: (_, __) => dragUpdates++,
    );

    final emptyCanvasPoint = _globalForScene(tester, const Offset(40, 40));
    await tester.dragFrom(emptyCanvasPoint, const Offset(80, 40));
    await tester.pumpAndSettle();

    expect(dragUpdates, 0);
    expect(controller.isCameraGated, isFalse);

    final scaleBefore = controller.currentScale;
    controller.zoomBy(1.2);
    expect(controller.currentScale, greaterThan(scaleBefore));

    controller.dispose();
  });

  testWidgets('touch long-press without movement captures the node',
      (tester) async {
    final controller = _TestHarness.newController();
    Node<int>? dragged;

    await _pumpGraph(
      tester,
      controller: controller,
      onNodeDragStart: (node, _) => dragged = node,
    );

    final nodeCentre = _nodeCenter(tester, _TestHarness.bottom);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.touch);
    await gesture.down(nodeCentre);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(dragged, _TestHarness.bottom);
    expect(controller.isCameraGated, isTrue);

    await gesture.up();
    await tester.pump();
    expect(controller.isCameraGated, isFalse);

    controller.dispose();
  });

  testWidgets('touch movement before long-press cancels pending capture',
      (tester) async {
    final controller = _TestHarness.newController();
    Node<int>? dragged;
    var dragUpdates = 0;

    await _pumpGraph(
      tester,
      controller: controller,
      onNodeDragStart: (node, _) => dragged = node,
      onNodeDragUpdate: (_, __) => dragUpdates++,
    );

    final nodeCentre = _nodeCenter(tester, _TestHarness.bottom);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.touch);
    await gesture.down(nodeCentre);
    await gesture.moveBy(Offset(kTouchSlop + 1, 0));
    await tester.pump(const Duration(milliseconds: 600));

    expect(dragged, isNull);
    expect(dragUpdates, 0);
    expect(controller.isCameraGated, isFalse);

    await gesture.up();
    controller.dispose();
  });

  testWidgets('two-pointer scale before capture keeps camera and skips node drag',
      (tester) async {
    final controller = _TestHarness.newController();
    Node<int>? dragged;
    var dragUpdates = 0;

    await _pumpGraph(
      tester,
      controller: controller,
      onNodeDragStart: (node, _) => dragged = node,
      onNodeDragUpdate: (_, __) => dragUpdates++,
    );

    final nodeCentre = _nodeCenter(tester, _TestHarness.bottom);
    final gestureA = await tester.createGesture(kind: PointerDeviceKind.touch);
    await gestureA.down(nodeCentre);
    await tester.pump(const Duration(milliseconds: 100));

    final gestureB = await tester.createGesture(kind: PointerDeviceKind.touch);
    await gestureB.down(nodeCentre + const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 600));

    expect(dragged, isNull);
    expect(dragUpdates, 0);
    expect(controller.isCameraGated, isFalse);

    await gestureA.up();
    await gestureB.up();
    controller.dispose();
  });

  testWidgets('additional finger after capture keeps node ownership', (tester) async {
    final controller = _TestHarness.newController();
    final updates = <Offset>[];

    await _pumpGraph(
      tester,
      controller: controller,
      onNodeDragUpdate: (_, position) => updates.add(position),
    );

    final nodeCentre = _nodeCenter(tester, _TestHarness.bottom);
    final primary = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await primary.down(nodeCentre);
    await primary.moveBy(const Offset(20, 0));
    await tester.pump();

    final secondary = await tester.createGesture(kind: PointerDeviceKind.touch);
    await secondary.down(nodeCentre + const Offset(20, 20));
    await tester.pump();

    expect(controller.isCameraGated, isTrue);

    await primary.moveBy(const Offset(30, 0));
    await tester.pump();
    expect(updates.length, greaterThan(1));
    expect(controller.getPosition(_TestHarness.bottom).dx, greaterThan(130));

    await primary.up();
    expect(controller.isCameraGated, isTrue);

    await secondary.up();
    await tester.pump();
    expect(controller.isCameraGated, isFalse);

    controller.dispose();
  });

  testWidgets('remaining finger after primary lift keeps camera gated until release',
      (tester) async {
    final controller = _TestHarness.newController();

    await _pumpGraph(
      tester,
      controller: controller,
      onNodeDragUpdate: (node, position) {
        controller.setNodePresentationPosition(node, position);
      },
    );

    final nodeCentre = _nodeCenter(tester, _TestHarness.bottom);
    final primary = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await primary.down(nodeCentre);
    await primary.moveBy(const Offset(20, 0));
    await tester.pump();

    final secondary = await tester.createGesture(kind: PointerDeviceKind.touch);
    await secondary.down(nodeCentre + const Offset(16, 16));
    await tester.pump();

    await primary.up();
    expect(controller.isCameraGated, isTrue);

    await secondary.up();
    await tester.pump();
    expect(controller.isCameraGated, isFalse);

    controller.dispose();
  });

  testWidgets('pointer cancel clears presentation and notifies cancel', (tester) async {
    final controller = _TestHarness.newController();
    Node<int>? cancelled;
    var endCount = 0;

    await _pumpGraph(
      tester,
      controller: controller,
      onNodeDragCancel: (node) => cancelled = node,
      onNodeDragEnd: (_, __) => endCount++,
      onNodeDragUpdate: (node, position) {
        controller.setNodePresentationPosition(node, position);
      },
    );

    final nodeCentre = _nodeCenter(tester, _TestHarness.bottom);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(nodeCentre);
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    expect(
      controller.getPosition(_TestHarness.bottom),
      isNot(controller.layout.getPosition(_TestHarness.bottom)),
    );

    await gesture.cancel();
    await tester.pump();

    expect(cancelled, _TestHarness.bottom);
    expect(endCount, 0);
    expect(
      controller.getPosition(_TestHarness.bottom),
      controller.layout.getPosition(_TestHarness.bottom),
    );

    controller.dispose();
  });

  testWidgets('topmost overlap hit follows shared paint order', (tester) async {
    final controller = _TestHarness.newController();
    Node<int>? dragged;

    await _pumpGraph(
      tester,
      controller: controller,
      layoutAlgorithm: const _OverlappingFixedLayout(),
      nodePaintOrder: const [_TestHarness.bottom, _TestHarness.top],
      onNodeDragStart: (node, _) => dragged = node,
    );

    final overlap = _nodeCenter(tester, _TestHarness.bottom);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(overlap);
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();

    expect(dragged, _TestHarness.top);

    await gesture.up();
    controller.dispose();
  });

  testWidgets('drag updates only moved node and incident edge geometry in one frame',
      (tester) async {
    final controller = _TestHarness.newController();
    final recorder = _EdgeGeometryRecorder();

    await _pumpGraph(
      tester,
      controller: controller,
      edgePainter: recorder,
      onNodeDragUpdate: (node, position) {
        controller.setNodePresentationPosition(node, position);
      },
    );

    final unrelatedBefore = recorder.snapshotFor(_TestHarness.unrelatedEdge);
    final nodeCentre = _nodeCenter(tester, _TestHarness.bottom);
    final layoutCentre = controller.layout.getPosition(_TestHarness.bottom);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(nodeCentre);
    await gesture.moveBy(const Offset(35, 0));
    await tester.pump();

    final movedCentre = controller.getPosition(_TestHarness.bottom);
    final incident = recorder.lastFrameFor(_TestHarness.edge);
    final unrelatedAfter = recorder.snapshotFor(_TestHarness.unrelatedEdge);

    expect(movedCentre.dx, greaterThan(layoutCentre.dx));
    expect(movedCentre.dy, closeTo(layoutCentre.dy, 0.01));
    expect(incident.destination, movedCentre);
    expect(incident.source, controller.getPosition(_TestHarness.middle));
    expect(unrelatedAfter, unrelatedBefore);

    await gesture.up();
    controller.dispose();
  });

  testWidgets('drag moves do not trigger global relayout', (tester) async {
    final controller = _TestHarness.newController();
    final algorithm = _CountingLayoutAlgorithm();

    await _pumpGraph(
      tester,
      controller: controller,
      layoutAlgorithm: algorithm,
      onNodeDragUpdate: (node, position) {
        controller.setNodePresentationPosition(node, position);
      },
    );

    final relayoutsAfterSetup = controller.relayoutInvocationCount;
    final relayoutCallsAfterSetup = algorithm.relayoutCalls;
    final nodeCentre = _nodeCenter(tester, _TestHarness.bottom);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(nodeCentre);
    for (var i = 0; i < 5; i++) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();

    expect(controller.relayoutInvocationCount, relayoutsAfterSetup);
    expect(algorithm.relayoutCalls, relayoutCallsAfterSetup);

    controller.dispose();
  });
}

class _TestHarness {
  static const top = Node<int>(data: 1, size: 100);
  static const middle = Node<int>(data: 2, size: 100);
  static const bottom = Node<int>(data: 3, size: 100);
  static const far = Node<int>(data: 4, size: 100);
  static const edge = Edge<Node<int>, int>(
    source: middle,
    destination: bottom,
    data: 1,
  );
  static const unrelatedEdge = Edge<Node<int>, int>(
    source: top,
    destination: far,
    data: 2,
  );

  static GraphController<Node<int>, Edge<Node<int>, int>> newController() =>
      testIntIntGraphController();
}

Future<void> _pumpGraph(
  WidgetTester tester, {
  required GraphController<Node<int>, Edge<Node<int>, int>> controller,
  GraphLayoutAlgorithm? layoutAlgorithm,
  EdgePainter<Node<int>, Edge<Node<int>, int>>? edgePainter,
  NodeDragStartCallback<Node<int>>? onNodeDragStart,
  NodeDragUpdateCallback<Node<int>>? onNodeDragUpdate,
  NodeDragEndCallback<Node<int>>? onNodeDragEnd,
  NodeDragCancelCallback<Node<int>>? onNodeDragCancel,
  List<Node<int>>? nodePaintOrder,
}) async {
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: SizedBox(
        width: 800,
        height: 600,
        child: GraphView<Node<int>, Edge<Node<int>, int>>(
          controller: controller,
          canvasSize: const GraphCanvasSize.fixed(Size(500, 500)),
          layoutAlgorithm: layoutAlgorithm ?? const _FixedLayout(),
          edgePainter: edgePainter ?? const LineEdgePainter(),
          nodePaintOrder: nodePaintOrder,
          onNodeDragStart: onNodeDragStart,
          onNodeDragUpdate: onNodeDragUpdate,
          onNodeDragEnd: onNodeDragEnd,
          onNodeDragCancel: onNodeDragCancel,
          nodeBuilder: (context, node) => SizedBox(
            width: node.size,
            height: node.size,
            child: Text('${node.data}'),
          ),
        ),
      ),
    ),
  );

  controller.mutate((m) {
    m
      ..addNode(_TestHarness.top)
      ..addNode(_TestHarness.middle)
      ..addNode(_TestHarness.bottom)
      ..addNode(_TestHarness.far)
      ..addEdge(_TestHarness.edge)
      ..addEdge(_TestHarness.unrelatedEdge);
  });
  await tester.pumpAndSettle();
}

Offset _nodeCenter(WidgetTester tester, Node<int> node) =>
    _globalForScene(tester, _controllerFromTester(tester).getPosition(node));

GraphController<Node<int>, Edge<Node<int>, int>> _controllerFromTester(
  WidgetTester tester,
) {
  final element = tester.element(find.byType(GraphView<Node<int>, Edge<Node<int>, int>>));
  final state = element as StatefulElement;
  final graphView = state.widget as GraphView<Node<int>, Edge<Node<int>, int>>;
  return graphView.controller;
}

Offset _globalForScene(WidgetTester tester, Offset scene) {
  final box = tester.renderObject<RenderBox>(find.byType(GraphLayoutView));
  return box.localToGlobal(scene);
}

final class _OverlappingFixedLayout implements GraphLayoutAlgorithm {
  const _OverlappingFixedLayout();

  @override
  Stream<GraphLayout> layout({
    required Set<NodeBase> nodes,
    required Set<EdgeBase> edges,
    required Size size,
  }) =>
      Stream.value(_FixedLayout._build(nodes, overlapTopAndBottom: true));

  @override
  Stream<GraphLayout> relayout({
    required GraphLayout existingLayout,
    required Set<NodeBase> nodes,
    required Set<EdgeBase> edges,
    required Size size,
  }) =>
      Stream.value(_FixedLayout._build(nodes, overlapTopAndBottom: true));
}

final class _FixedLayout implements GraphLayoutAlgorithm {
  const _FixedLayout();

  static GraphLayout _build(
    Set<NodeBase> nodes, {
    bool overlapTopAndBottom = false,
  }) {
    final builder = GraphLayoutBuilder(nodes: {...nodes});
    if (nodes.contains(_TestHarness.top)) {
      builder.setNodePosition(
        _TestHarness.top,
        overlapTopAndBottom
            ? const Offset(150, 250)
            : const Offset(150, 150),
      );
    }
    if (nodes.contains(_TestHarness.middle)) {
      builder.setNodePosition(_TestHarness.middle, const Offset(250, 250));
    }
    if (nodes.contains(_TestHarness.bottom)) {
      builder.setNodePosition(_TestHarness.bottom, const Offset(150, 250));
    }
    if (nodes.contains(_TestHarness.far)) {
      builder.setNodePosition(_TestHarness.far, const Offset(400, 400));
    }
    return builder.build();
  }

  @override
  Stream<GraphLayout> layout({
    required Set<NodeBase> nodes,
    required Set<EdgeBase> edges,
    required Size size,
  }) =>
      Stream.value(_build(nodes));

  @override
  Stream<GraphLayout> relayout({
    required GraphLayout existingLayout,
    required Set<NodeBase> nodes,
    required Set<EdgeBase> edges,
    required Size size,
  }) =>
      Stream.value(_build(nodes));
}

final class _CountingLayoutAlgorithm implements GraphLayoutAlgorithm {
  var relayoutCalls = 0;

  @override
  Stream<GraphLayout> layout({
    required Set<NodeBase> nodes,
    required Set<EdgeBase> edges,
    required Size size,
  }) =>
      Stream.value(_FixedLayout._build(nodes));

  @override
  Stream<GraphLayout> relayout({
    required GraphLayout existingLayout,
    required Set<NodeBase> nodes,
    required Set<EdgeBase> edges,
    required Size size,
  }) {
    relayoutCalls++;
    return Stream.value(_FixedLayout._build(nodes));
  }
}

final class _EdgeGeometryRecorder
    implements EdgePainter<Node<int>, Edge<Node<int>, int>> {
  _EdgeGeometryRecorder();

  final _frames = <Edge<Node<int>, int>, _EdgeFrame>{};

  _EdgeFrame snapshotFor(Edge<Node<int>, int> edge) =>
      _frames[edge] ?? _EdgeFrame.zero;

  _EdgeFrame lastFrameFor(Edge<Node<int>, int> edge) => _frames[edge]!;

  @override
  void paint(
    Canvas canvas,
    Edge<Node<int>, int> edge,
    Offset sourcePosition,
    Offset destinationPosition,
  ) {
    _frames[edge] = _EdgeFrame(
      source: sourcePosition,
      destination: destinationPosition,
    );
  }
}

final class _EdgeFrame {
  const _EdgeFrame({
    required this.source,
    required this.destination,
  });

  static const zero = _EdgeFrame(
    source: Offset.zero,
    destination: Offset.zero,
  );

  final Offset source;
  final Offset destination;

  @override
  bool operator ==(Object other) =>
      other is _EdgeFrame &&
      other.source == source &&
      other.destination == destination;

  @override
  int get hashCode => Object.hash(source, destination);
}
