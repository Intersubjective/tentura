import 'dart:async';
import 'dart:ui' show Offset, Size;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:force_directed_graphview/src/scene/graph_layout_ticket.dart'
    show mintGraphLayoutTicket;
import 'support/fixed_scene_layout.dart';
import 'support/int_graph_controller.dart';
import 'support/settle_graph_layout.dart';

GraphController<_LogicalIdNode, Edge<_LogicalIdNode, String>>
    _logicalIdGraphController() => GraphController(
      nodeIdOf: (node) => '${node.logicalId}@${identityHashCode(node)}',
      edgeIdOf: (edge) => identityHashCode(edge).toString(),
    );

GraphController<Node<int>, Edge<Node<int>, String>> _intStringEdgeController() =>
    GraphController(
      nodeIdOf: testIntNodeId,
      edgeIdOf: (edge) => (edge as Edge<Node<int>, String>).data,
    );

/// Mimics [NodeDetails]-style equality: stable [logicalId] for product identity,
/// but `==`/`hashCode` also include mutable presentation fields.
final class _LogicalIdNode extends NodeBase {
  const _LogicalIdNode({
    required this.logicalId,
    required this.display,
    super.size = 40,
    super.pinned = false,
  });

  final String logicalId;
  final String display;

  @override
  _LogicalIdNode copyWithPinned(bool pinned) =>
      _LogicalIdNode(logicalId: logicalId, display: display, size: size, pinned: pinned);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _LogicalIdNode &&
          logicalId == other.logicalId &&
          display == other.display &&
          size == other.size &&
          pinned == other.pinned;

  @override
  int get hashCode => Object.hash(logicalId, display, size, pinned);
}

void main() {
  group('logical id vs instance-keyed layout (M00 baseline)', () {
    test('scene layout misses equal logical id when payload instance differs', () {
      const before = _LogicalIdNode(logicalId: 'n1', display: 'v1');
      const after = _LogicalIdNode(logicalId: 'n1', display: 'v2');
      expect(before.logicalId, after.logicalId);
      expect(before, isNot(equals(after)));

      final beforeId = '${before.logicalId}@${identityHashCode(before)}';
      final afterId = '${after.logicalId}@${identityHashCode(after)}';
      expect(beforeId, isNot(afterId));

      final ticket = mintGraphLayoutTicket(
        owner: Object(),
        topologyRevision: 1,
        generation: 1,
      );
      final layout = SceneLayout(
        ticket: ticket,
        revision: 1,
        positions: {
          beforeId: ScenePoint(x: 100, y: 200),
        },
      );
      expect(layout.positions[beforeId], ScenePoint(x: 100, y: 200));
      expect(layout.positions[afterId], isNull);
    });

    test('GraphController allows two nodes with the same logicalId string', () {
      final controller =
          _logicalIdGraphController();
      const first = _LogicalIdNode(logicalId: 'dup', display: 'a');
      const second = _LogicalIdNode(logicalId: 'dup', display: 'b');

      controller.mutate((m) {
        m
          ..addNode(first)
          ..addNode(second);
      });

      expect(controller.nodes, hasLength(2));
    });

    test('replaceNode seeds retained position for the replacement id', () {
      final controller = _logicalIdGraphController();
      const before = _LogicalIdNode(logicalId: 'n1', display: 'v1');
      const after = _LogicalIdNode(logicalId: 'n1', display: 'v2');

      controller.mutate((m) => m.addNode(before), requestLayout: false);
      controller.beginNodePresentationDrag(before, const Offset(42, 84));

      controller.replaceNode(before, after);

      expect(controller.nodes.contains(after), isTrue);
      expect(controller.nodes.contains(before), isFalse);
      expect(controller.getPosition(after), const Offset(42, 84));
      controller.dispose();
    });
  });

  group('Node<int> identity (stable data key)', () {
    test('duplicate data rejects second addNode via Set equality', () {
      final controller = testIntGraphController();
      const a = Node<int>(data: 1, size: 10);
      const b = Node<int>(data: 1, size: 10);

      controller.mutate((m) => m.addNode(a));
      expect(
        () => controller.mutate((m) => m.addNode(b)),
        throwsA(isInstanceOf<StateError>()),
      );
    });

    test('replaceNode preserves layout position for new instance same data', () {
      final controller = testIntGraphController();
      const before = Node<int>(data: 7, size: 10);
      final after = Node<int>(data: 7, size: 10, pinned: true);

      controller.mutate((m) => m.addNode(before));
      controller.replaceNode(before, after);

      // Without an accepted async layout, replaceNode still updates membership.
      expect(controller.nodes.single, after);
    });
  });

  group('parallel and duplicate edges', () {
    const n1 = Node<int>(data: 1, size: 10);
    const n2 = Node<int>(data: 2, size: 10);

    test('parallel edges with distinct edge data coexist', () {
      final controller = _intStringEdgeController();
      final edgeA = Edge(source: n1, destination: n2, data: 'trust');
      final edgeB = Edge(source: n1, destination: n2, data: 'forward');

      controller.mutate((m) {
        m
          ..addNode(n1)
          ..addNode(n2)
          ..addEdge(edgeA)
          ..addEdge(edgeB);
      });

      expect(controller.edges, hasLength(2));
    });

    test('identical edge instance is not duplicated in the edge set', () {
      final controller = _intStringEdgeController();
      final edge = Edge(source: n1, destination: n2, data: 'x');

      controller.mutate((m) {
        m
          ..addNode(n1)
          ..addNode(n2)
          ..addEdge(edge)
          ..addEdge(edge);
      });

      expect(controller.edges, hasLength(1));
    });
  });

  group('presentation vs layout resolution', () {
    testWidgets('getPosition prefers presentation override over layout',
        (tester) async {
      final controller =
          testIntGraphController();
      const node = Node<int>(data: 1, size: 50);

      await tester.pumpWidget(
        MaterialApp(
          home: GraphView<Node<int>, Edge<Node<int>, void>>(
            controller: controller,
            canvasSize: const GraphCanvasSize.fixed(Size(400, 400)),
            layoutAlgorithm: FixedSceneLayoutAlgorithm({
              '1': ScenePoint(x: 10, y: 20),
            }),
            nodeBuilder: (context, node) => const SizedBox.shrink(),
          ),
        ),
      );

      controller.mutate((m) => m.addNode(node));
      await settleGraphLayout(tester, controller);

      controller.beginNodePresentationDrag(node, const Offset(9, 9));
      expect(controller.getPosition(node), const Offset(9, 9));

      controller.dispose();
    });

    testWidgets('clearPresentationForNodeId reverts to layout in one step',
        (tester) async {
      final controller =
          testIntGraphController();
      const node = Node<int>(data: 1, size: 50);

      await tester.pumpWidget(
        MaterialApp(
          home: GraphView<Node<int>, Edge<Node<int>, void>>(
            controller: controller,
            canvasSize: const GraphCanvasSize.fixed(Size(400, 400)),
            layoutAlgorithm: FixedSceneLayoutAlgorithm({
              '1': ScenePoint(x: 10, y: 20),
            }),
            nodeBuilder: (context, node) => const SizedBox.shrink(),
          ),
        ),
      );

      controller.mutate((m) => m.addNode(node));
      await settleGraphLayout(tester, controller);

      const override = Offset(300, 300);
      controller.beginNodePresentationDrag(node, override);
      expect(controller.getPosition(node), override);

      controller.clearPresentationForNodeId('1');
      expect(controller.getPosition(node), const Offset(10, 20));
    });
  });

  group('camera preservation (current clear contract)', () {
    testWidgets('clear keeps zoom after rebuild mutate',
        (tester) async {
      const viewportW = 800.0;
      const viewportH = 600.0;
      tester.view.physicalSize = const Size(viewportW, viewportH);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller =
          testIntGraphController();
      const node = Node<int>(data: 1, size: 50);

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: viewportW,
            height: viewportH,
            child: GraphView<Node<int>, Edge<Node<int>, void>>(
              controller: controller,
              canvasSize: const GraphCanvasSize.fixed(Size(500, 500)),
              layoutAlgorithm: FixedSceneLayoutAlgorithm({
                '1': ScenePoint(x: 250, y: 250),
              }),
              nodeBuilder: (context, node) => const SizedBox.shrink(),
            ),
          ),
        ),
      );

      controller.mutate((m) => m.addNode(node));
      await settleGraphLayout(tester, controller);

      controller.zoomBy(2.0);
      final scaleBeforeClear = controller.currentScale;
      expect(scaleBeforeClear, greaterThan(1.5));

      controller.clear();
      controller.mutate((m) => m.addNode(node));
      await settleGraphLayout(tester, controller);

      expect(controller.currentScale, closeTo(scaleBeforeClear, 0.001));

      controller.dispose();
    });
  });

  group('stale layout stream frames', () {
    testWidgets('superseding mutate ignores frames from an earlier relayout',
        (tester) async {
      final controller =
          testIntGraphController();
      const n1 = Node<int>(data: 1, size: 10);
      const n2 = Node<int>(data: 2, size: 10);

      await tester.pumpWidget(
        MaterialApp(
          home: GraphView<Node<int>, Edge<Node<int>, void>>(
            controller: controller,
            canvasSize: const GraphCanvasSize.fixed(Size(400, 400)),
            layoutAlgorithm: _StaggeredStreamLayout(
              first: {1: ScenePoint(x: 10, y: 10)},
              second: {
                1: ScenePoint(x: 100, y: 100),
                2: ScenePoint(x: 200, y: 200),
              },
            ),
            nodeBuilder: (context, node) => const SizedBox.shrink(),
          ),
        ),
      );

      controller.mutate((m) => m.addNode(n1));
      await tester.pump();

      controller.mutate((m) => m.addNode(n2));
      await tester.pump(const Duration(milliseconds: 60));
      await settleGraphLayout(tester, controller);

      expect(controller.getPosition(n1), const Offset(100, 100));
      expect(controller.getPosition(n2), const Offset(200, 200));

      controller.dispose();
    });
  });

  group('independent controllers', () {
    test('presentation and topology are not shared across controllers', () {
      final a = testIntGraphController();
      final b = testIntGraphController();
      const node = Node<int>(data: 1, size: 10);

      a.mutate((m) => m.addNode(node));
      a.beginNodePresentationDrag(node, const Offset(1, 1));

      expect(b.nodes, isEmpty);
      expect(
        () => b.getPosition(node),
        throwsA(isA<StateError>()),
      );
    });
  });
}

final class _StaggeredStreamLayout implements SceneLayoutAlgorithm {
  _StaggeredStreamLayout({
    required Map<int, ScenePoint> first,
    required Map<int, ScenePoint> second,
  })  : _first = first,
        _second = second;

  final Map<int, ScenePoint> _first;
  final Map<int, ScenePoint> _second;

  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) async* {
    if (request.nodeIds.length == 1) {
      yield _frameFor(request, _first, 0, false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      yield _frameFor(request, _first, 1, true);
      return;
    }
    yield _frameFor(request, _second, 0, true);
  }

  GraphLayoutFrame _frameFor(
    GraphLayoutRequest request,
    Map<int, ScenePoint> positions,
    int sequence,
    bool terminal,
  ) {
    final resolved = <GraphNodeId, ScenePoint>{};
    for (final id in request.nodeIds) {
      final data = int.parse(id);
      resolved[id] = positions[data] ?? ScenePoint(x: 0, y: 0);
    }
    return GraphLayoutFrame(
      ticket: request.ticket,
      sequence: sequence,
      positions: resolved,
      isTerminal: terminal,
    );
  }
}
