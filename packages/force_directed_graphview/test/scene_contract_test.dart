import 'dart:async';
import 'dart:ui' show Offset, Size;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'support/int_graph_controller.dart';

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
    test('GraphLayout map misses equal logical id when payload fields differ', () {
      const before = _LogicalIdNode(logicalId: 'n1', display: 'v1');
      const after = _LogicalIdNode(logicalId: 'n1', display: 'v2');
      expect(before.logicalId, after.logicalId);
      expect(before, isNot(equals(after)));

      final builder = GraphLayoutBuilder(nodes: {before})
        ..setNodePosition(before, const Offset(100, 200));
      final layout = builder.build();

      expect(layout.getPositionOrNull(before), const Offset(100, 200));
      expect(layout.getPositionOrNull(after), isNull);
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

    testWidgets('replaceNode moves layout position to the replacement instance',
        (tester) async {
      final controller =
          _logicalIdGraphController();
      const before = _LogicalIdNode(logicalId: 'n1', display: 'v1');
      const after = _LogicalIdNode(logicalId: 'n1', display: 'v2');

      await tester.pumpWidget(
        MaterialApp(
          home: GraphView<_LogicalIdNode, Edge<_LogicalIdNode, String>>(
            controller: controller,
            canvasSize: const GraphCanvasSize.fixed(Size(400, 400)),
            layoutAlgorithm: _LogicalIdFixedLayout(
              positions: {before: const Offset(42, 84)},
            ),
            nodeBuilder: (context, node) => const SizedBox.shrink(),
          ),
        ),
      );

      controller.mutate((m) => m.addNode(before));
      await tester.pumpAndSettle();

      controller.replaceNode(before, after);

      expect(controller.nodes.contains(after), isTrue);
      expect(controller.nodes.contains(before), isFalse);
      expect(controller.layout.getPosition(after), const Offset(42, 84));

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
            layoutAlgorithm: const _FixedSingleNodeLayout(
              position: Offset(10, 20),
            ),
            nodeBuilder: (context, node) => const SizedBox.shrink(),
          ),
        ),
      );

      controller.mutate((m) => m.addNode(node));
      await tester.pumpAndSettle();

      controller.setNodePresentationPosition(node, const Offset(9, 9));
      expect(controller.getPosition(node), const Offset(9, 9));

      controller.dispose();
    });

    testWidgets('clearPresentationPosition reverts to layout in one step',
        (tester) async {
      final controller =
          testIntGraphController();
      const node = Node<int>(data: 1, size: 50);

      await tester.pumpWidget(
        MaterialApp(
          home: GraphView<Node<int>, Edge<Node<int>, void>>(
            controller: controller,
            canvasSize: const GraphCanvasSize.fixed(Size(400, 400)),
            layoutAlgorithm: const _FixedSingleNodeLayout(
              position: Offset(10, 20),
            ),
            nodeBuilder: (context, node) => const SizedBox.shrink(),
          ),
        ),
      );

      controller.mutate((m) => m.addNode(node));
      await tester.pumpAndSettle();

      const override = Offset(300, 300);
      controller.setNodePresentationPosition(node, override);
      expect(controller.getPosition(node), override);

      controller.clearPresentationPosition(node);
      expect(controller.getPosition(node), const Offset(10, 20));
    });
  });

  group('camera preservation (current clear contract)', () {
    testWidgets('clear(recenter: false) keeps zoom after rebuild mutate',
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
              layoutAlgorithm: const _FixedSingleNodeLayout(
                position: Offset(250, 250),
              ),
              nodeBuilder: (context, node) => const SizedBox.shrink(),
            ),
          ),
        ),
      );

      controller.mutate((m) => m.addNode(node));
      await tester.pumpAndSettle();

      controller.zoomBy(2.0);
      final scaleBeforeClear = controller.currentScale;
      expect(scaleBeforeClear, greaterThan(1.5));

      controller.clear(recenter: false);
      controller.mutate((m) => m.addNode(node));
      await tester.pumpAndSettle();

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
              first: const {1: Offset(10, 10)},
              second: const {1: Offset(100, 100), 2: Offset(200, 200)},
            ),
            nodeBuilder: (context, node) => const SizedBox.shrink(),
          ),
        ),
      );

      controller.mutate((m) => m.addNode(n1));
      await tester.pump();

      controller.mutate((m) => m.addNode(n2));
      await tester.pumpAndSettle();

      expect(controller.layout.getPosition(n1), const Offset(100, 100));
      expect(controller.layout.getPosition(n2), const Offset(200, 200));

      controller.dispose();
    });
  });

  group('independent controllers', () {
    test('presentation and topology are not shared across controllers', () {
      final a = testIntGraphController();
      final b = testIntGraphController();
      const node = Node<int>(data: 1, size: 10);

      a.mutate((m) => m.addNode(node));
      a.setNodePresentationPosition(node, const Offset(1, 1));

      expect(b.nodes, isEmpty);
      expect(
        () => b.getPosition(node),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

final class _LogicalIdFixedLayout implements GraphLayoutAlgorithm {
  _LogicalIdFixedLayout({required this.positions});

  final Map<_LogicalIdNode, Offset> positions;

  @override
  Stream<GraphLayout> layout({
    required Set<NodeBase> nodes,
    required Set<EdgeBase> edges,
    required Size size,
  }) {
    final builder = GraphLayoutBuilder(nodes: {...nodes});
    for (final node in nodes) {
      if (node is _LogicalIdNode) {
        builder.setNodePosition(node, positions[node] ?? Offset.zero);
      }
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

final class _FixedSingleNodeLayout implements GraphLayoutAlgorithm {
  const _FixedSingleNodeLayout({required this.position});

  final Offset position;

  @override
  Stream<GraphLayout> layout({
    required Set<NodeBase> nodes,
    required Set<EdgeBase> edges,
    required Size size,
  }) {
    final builder = GraphLayoutBuilder(nodes: {...nodes});
    for (final node in nodes) {
      builder.setNodePosition(node, position);
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

final class _StaggeredStreamLayout implements GraphLayoutAlgorithm {
  _StaggeredStreamLayout({
    required Map<int, Offset> first,
    required Map<int, Offset> second,
  })  : _first = first,
        _second = second;

  final Map<int, Offset> _first;
  final Map<int, Offset> _second;

  @override
  Stream<GraphLayout> layout({
    required Set<NodeBase> nodes,
    required Set<EdgeBase> edges,
    required Size size,
  }) async* {
    if (nodes.length == 1) {
      yield _layoutFor(nodes, _first);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      yield _layoutFor(nodes, _first);
      return;
    }
    yield _layoutFor(nodes, _second);
  }

  @override
  Stream<GraphLayout> relayout({
    required GraphLayout existingLayout,
    required Set<NodeBase> nodes,
    required Set<EdgeBase> edges,
    required Size size,
  }) =>
      layout(nodes: nodes, edges: edges, size: size);

  GraphLayout _layoutFor(Set<NodeBase> nodes, Map<int, Offset> positions) {
    final builder = GraphLayoutBuilder(nodes: {...nodes});
    for (final node in nodes) {
      if (node is Node<int>) {
        builder.setNodePosition(
          node,
          positions[node.data] ?? Offset.zero,
        );
      }
    }
    return builder.build();
  }
}
