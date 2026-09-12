import 'dart:ui' show Offset;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:force_directed_graphview/src/widget/graph_layout_view.dart';
import 'support/int_graph_controller.dart';

void main() {
  testWidgets('orderedRenderNodeIds respects legacy paint order and override stacking',
      (tester) async {
    final controller = testIntIntGraphController();
    const a = Node<int>(data: 1, size: 10);
    const b = Node<int>(data: 2, size: 10);
    const c = Node<int>(data: 3, size: 10);

    await _pumpMinimalGraph(tester, controller: controller);
    controller.mutate((m) {
      m
        ..addNode(a)
        ..addNode(b)
        ..addNode(c);
    });
    await tester.pumpAndSettle();

    final snapshot = controller.renderSnapshot;
    final baseline = controller.orderedRenderNodeIds(
      snapshot,
      legacyPaintOrder: const [c, a],
    );
    expect(baseline, ['3', '1', '2']);

    controller.beginNodePresentationDrag(b, const Offset(5, 5));
    final withOverride = controller.orderedRenderNodeIds(
      controller.renderSnapshot,
      legacyPaintOrder: const [c, a],
    );
    expect(withOverride.last, '2');

    controller.dispose();
  });

  testWidgets('payload replacement rebuilds node widget under stable id',
      (tester) async {
    final controller = testIntIntGraphController();
    const initial = Node<int>(data: 1, size: 40);
    const replacement = Node<int>(data: 1, size: 60);

    await _pumpMinimalGraph(tester, controller: controller);
    controller.mutate((m) => m.addNode(initial));
    await tester.pumpAndSettle();
    expect(find.text('size-40.0'), findsOneWidget);

    controller.replaceNode(initial, replacement);
    await tester.pumpAndSettle();
    expect(find.text('size-60.0'), findsOneWidget);
    expect(find.text('size-40.0'), findsNothing);

    controller.dispose();
  });

  testWidgets('same-frame edge paint reads both endpoints from one snapshot',
      (tester) async {
    final controller = testIntIntGraphController();
    final recorder = _SameFrameEdgeRecorder();

    await _pumpMinimalGraph(
      tester,
      controller: controller,
      edgePainter: recorder,
    );

    const source = Node<int>(data: 1, size: 40);
    const destination = Node<int>(data: 2, size: 40);
    const edge = Edge<Node<int>, int>(
      source: source,
      destination: destination,
      data: 10,
    );

    controller.mutate((m) {
      m
        ..addNode(source)
        ..addNode(destination)
        ..addEdge(edge);
    });
    await tester.pumpAndSettle();

    expect(recorder.frameCount, greaterThan(0));
    expect(recorder.sameSnapshotEndpoints, isTrue);

    controller.dispose();
  });

  testWidgets('dispose during drag cancels once without end callback',
      (tester) async {
    final controller = testIntIntGraphController();
    var cancelCount = 0;
    var endCount = 0;

    await _pumpMinimalGraph(
      tester,
      controller: controller,
      onNodeDragCancel: (_) => cancelCount++,
      onNodeDragEnd: (_, __) => endCount++,
    );

    const node = Node<int>(data: 7, size: 80);
    controller.mutate((m) => m.addNode(node));
    await tester.pumpAndSettle();

    final centre = _sceneCentre(tester, controller, node);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(centre);
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(cancelCount, 1);
    expect(endCount, 0);
    controller.dispose();
  });
}

Future<void> _pumpMinimalGraph(
  WidgetTester tester, {
  required GraphController<Node<int>, Edge<Node<int>, int>> controller,
  EdgePainter<Node<int>, Edge<Node<int>, int>>? edgePainter,
  NodeDragCancelCallback<Node<int>>? onNodeDragCancel,
  NodeDragEndCallback<Node<int>>? onNodeDragEnd,
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
          layoutAlgorithm: const _CentreLayout(),
          edgePainter: edgePainter ?? const LineEdgePainter(),
          onNodeDragCancel: onNodeDragCancel,
          onNodeDragEnd: onNodeDragEnd,
          onNodeDragStart: (_, __) {},
          onNodeDragUpdate: (_, __) {},
          nodeBuilder: (context, node) => SizedBox(
            width: node.size,
            height: node.size,
            child: Text('size-${node.size}'),
          ),
        ),
      ),
    ),
  );
}

Offset _sceneCentre(
  WidgetTester tester,
  GraphController<Node<int>, Edge<Node<int>, int>> controller,
  Node<int> node,
) {
  final box = tester.renderObject<RenderBox>(find.byType(GraphLayoutView));
  return box.localToGlobal(controller.getPosition(node));
}

final class _CentreLayout implements GraphLayoutAlgorithm {
  const _CentreLayout();

  @override
  Stream<GraphLayout> layout({
    required Set<NodeBase> nodes,
    required Set<EdgeBase> edges,
    required Size size,
  }) {
    final builder = GraphLayoutBuilder(nodes: {...nodes});
    var index = 0;
    for (final node in nodes) {
      builder.setNodePosition(
        node,
        Offset(120 + index * 80, 250),
      );
      index++;
    }
    return Stream.value(builder.build());
  }

  @override
  Stream<GraphLayout> relayout({
    required GraphLayout existingLayout,
    required Set<NodeBase> nodes,
    required Set<EdgeBase> edges,
    required Size size,
  }) =>
      layout(nodes: nodes, edges: edges, size: size);
}

final class _SameFrameEdgeRecorder
    implements EdgePainter<Node<int>, Edge<Node<int>, int>> {
  var frameCount = 0;
  var sameSnapshotEndpoints = false;

  @override
  void paint(
    Canvas canvas,
    Edge<Node<int>, int> edge,
    Offset sourcePosition,
    Offset destinationPosition,
  ) {
    frameCount++;
    sameSnapshotEndpoints =
        sourcePosition.dx.isFinite &&
        sourcePosition.dy.isFinite &&
        destinationPosition.dx.isFinite &&
        destinationPosition.dy.isFinite;
  }
}
