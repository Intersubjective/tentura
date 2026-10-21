import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'support/fixed_scene_layout.dart';
import 'support/int_graph_controller.dart';
import 'support/settle_graph_layout.dart';

typedef _Controller = GraphController<Node<int>, Edge<Node<int>, int>>;

const _n1 = Node<int>(data: 1, size: 40);
const _n2 = Node<int>(data: 2, size: 40);
const _n3 = Node<int>(data: 3, size: 40);
const _n4 = Node<int>(data: 4, size: 40);

// Edge data is the edge id: 10 and 13 touch node 1, 11 and 12 do not.
final _edges = {
  const Edge<Node<int>, int>(source: _n1, destination: _n2, data: 10),
  const Edge<Node<int>, int>(source: _n2, destination: _n3, data: 11),
  const Edge<Node<int>, int>(source: _n3, destination: _n4, data: 12),
  const Edge<Node<int>, int>(source: _n1, destination: _n4, data: 13),
};

void main() {
  group('Edges away from the dragged node are cached', () {
    testWidgets(
      'each drag frame paints exactly the edges incident to the dragged node',
      (tester) async {
        final harness = await _pumpGraph(tester);
        final controller = harness.controller;
        expect(
          harness.paintsOf(const [10, 11, 12, 13]),
          everyElement(greaterThan(0)),
          reason: 'Every edge has been painted before the drag',
        );

        final token = controller.beginNodePresentationDragForId(
          '1',
          const Offset(100, 100),
        );
        controller.updateNodePresentationDrag(token, const Offset(180, 130));
        await tester.pump();
        final before = harness.paintsOf(const [10, 11, 12, 13]);

        for (var step = 1; step <= 3; step++) {
          controller.updateNodePresentationDrag(
            token,
            Offset(180 + step * 20, 130 + step * 10),
          );
          await tester.pump();
        }
        final after = harness.paintsOf(const [10, 11, 12, 13]);

        expect(after[1], before[1], reason: 'edge 11 must come from the cache');
        expect(after[2], before[2], reason: 'edge 12 must come from the cache');
        expect(after[0] - before[0], 3, reason: 'edge 10 paints once a frame');
        expect(after[3] - before[3], 3, reason: 'edge 13 paints once a frame');
        controller.cancelNodePresentationDrag(token);
        controller.dispose();
      },
    );

    testWidgets(
      'a drag frame repaints one edge repaint boundary and leaves the other',
      (tester) async {
        final harness = await _pumpGraph(tester);
        final controller = harness.controller;
        final token = controller.beginNodePresentationDragForId(
          '1',
          const Offset(100, 100),
        );
        controller.updateNodePresentationDrag(token, const Offset(180, 130));
        await tester.pump();

        final edgeBoundaries = _edgeBoundaries(tester);
        final repaints = <RenderObject, int>{};
        debugOnProfilePaint = (object) {
          if (edgeBoundaries.contains(object)) {
            repaints.update(object, (c) => c + 1, ifAbsent: () => 1);
          }
        };
        try {
          for (var step = 1; step <= 3; step++) {
            controller.updateNodePresentationDrag(
              token,
              Offset(180 + step * 20, 130 + step * 10),
            );
            await tester.pump();
          }
        } finally {
          debugOnProfilePaint = null;
        }

        expect(
          edgeBoundaries.length,
          greaterThanOrEqualTo(2),
          reason: 'Cached and live edges need a repaint boundary each',
        );
        expect(
          edgeBoundaries
              .whereType<RenderRepaintBoundary>()
              .where((b) => b.debugLayer != null)
              .length,
          greaterThanOrEqualTo(2),
          reason: 'Each edge boundary keeps a layer of its own',
        );
        expect(
          repaints.length,
          1,
          reason: 'Only the live incident-edge boundary may repaint',
        );
        expect(repaints.values.single, 3);
        controller.cancelNodePresentationDrag(token);
        controller.dispose();
      },
    );

    testWidgets(
      'grab, drag frames and drop inflate and deactivate no edge elements '
      'beyond the live layer',
      (tester) async {
        final harness = await _pumpGraph(tester);
        final controller = harness.controller;
        final tracker = _ElementTracker(tester)
          ..observe()
          ..inflated = 0;
        final original = tracker.current.toSet();

        final token = controller.beginNodePresentationDragForId(
          '1',
          const Offset(100, 100),
        );
        controller.updateNodePresentationDrag(token, const Offset(200, 140));
        await tester.pump();
        tracker.observe();
        expect(tracker.deactivated, 0, reason: 'Grab must keep every element');
        final inflatedByGrab = tracker.inflated;
        expect(
          inflatedByGrab,
          lessThanOrEqualTo(6),
          reason: 'Grab may add only the live incident-edge layer',
        );

        for (var step = 1; step <= 3; step++) {
          controller.updateNodePresentationDrag(
            token,
            Offset(200 + step * 20, 140 + step * 10),
          );
          await tester.pump();
          tracker.observe();
        }
        expect(tracker.inflated, inflatedByGrab, reason: 'drag frames inflate');
        expect(tracker.deactivated, 0, reason: 'drag frames deactivate');

        controller.cancelNodePresentationDrag(token);
        await tester.pump();
        await tester.pump();
        await tester.pumpAndSettle();
        tracker.observe();
        expect(
          original.every(tracker.current.contains),
          isTrue,
          reason: 'Drop must keep the edge elements that existed at rest',
        );
        controller.dispose();
      },
    );
  });

  group('Edge cache invalidation', () {
    testWidgets(
      'an edge-style repaint notification repaints the cached edges',
      (tester) async {
        final harness = await _pumpGraph(tester);
        final controller = harness.controller;
        final token = controller.beginNodePresentationDragForId(
          '1',
          const Offset(100, 100),
        );
        controller.updateNodePresentationDrag(token, const Offset(180, 130));
        await tester.pump();
        final before = harness.paintsOf(const [10, 11, 12, 13]);

        harness.restyle.notifyListeners();
        await tester.pump();

        final after = harness.paintsOf(const [10, 11, 12, 13]);
        for (var i = 0; i < before.length; i++) {
          expect(after[i], greaterThan(before[i]));
        }
        controller.cancelNodePresentationDrag(token);
        controller.dispose();
      },
    );

    testWidgets(
      'a moved resting node repaints every edge that ends at it',
      (tester) async {
        final harness = await _pumpGraph(tester);
        final controller = harness.controller;
        final token = controller.beginNodePresentationDragForId(
          '1',
          const Offset(100, 100),
        );
        controller.updateNodePresentationDrag(token, const Offset(180, 130));
        await tester.pump();
        final before = harness.paintsOf(const [10, 11, 12, 13]);

        // Node 2 is an endpoint of edges 10 and 11 only.
        controller.requestSceneLayout(
          algorithm: FixedSceneLayoutAlgorithm({
            '1': ScenePoint(x: 100, y: 100),
            '2': ScenePoint(x: 320, y: 280),
            '3': ScenePoint(x: 100, y: 400),
            '4': ScenePoint(x: 400, y: 400),
          }),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 400));

        final after = harness.paintsOf(const [10, 11, 12, 13]);
        expect(after[0], greaterThan(before[0]), reason: 'edge 10');
        expect(after[1], greaterThan(before[1]), reason: 'edge 11');
        expect(
          after[2],
          before[2],
          reason: 'Edge 12 does not touch node 2, so its cache must hold',
        );
        controller.cancelNodePresentationDrag(token);
        controller.dispose();
      },
    );

    testWidgets(
      'replacing the edge painter during a drag repaints the cached edges',
      (tester) async {
        final harness = await _pumpGraph(tester);
        final controller = harness.controller;
        final token = controller.beginNodePresentationDragForId(
          '1',
          const Offset(100, 100),
        );
        controller.updateNodePresentationDrag(token, const Offset(180, 130));
        await tester.pump();
        final replacement = _RecordingEdgePainter(harness.restyle);

        await tester.pumpWidget(_graph(harness, replacement));
        await tester.pump();

        for (final id in const [10, 11, 12, 13]) {
          expect(replacement.paints[id], greaterThan(0), reason: 'edge $id');
        }
        controller.cancelNodePresentationDrag(token);
        controller.dispose();
      },
    );

    testWidgets(
      'an edge added during a drag appears and a removed one disappears',
      (tester) async {
        final harness = await _pumpGraph(tester);
        final controller = harness.controller;
        final token = controller.beginNodePresentationDragForId(
          '1',
          const Offset(100, 100),
        );
        controller.updateNodePresentationDrag(token, const Offset(180, 130));
        await tester.pump();
        controller.updateNodePresentationDrag(token, const Offset(200, 140));
        await tester.pump();

        // Edge 11 (2-3) midpoint and the midpoint of a new edge 2-4.
        const removedMid = Offset(200, 350);
        const addedMid = Offset(350, 350);
        expect(await _isInked(tester, harness, removedMid), isTrue);
        expect(await _isInked(tester, harness, addedMid), isFalse);

        final added = const Edge<Node<int>, int>(
          source: _n2,
          destination: _n4,
          data: 14,
        );
        controller.reconcileTopology(
          {_n1, _n2, _n3, _n4},
          {..._edges.where((e) => e.data != 11), added},
          requestLayout: false,
        );
        await tester.pump();
        controller.updateNodePresentationDrag(token, const Offset(210, 145));
        await tester.pump();

        expect(
          harness.paintsOf(const [14])[0],
          greaterThan(0),
          reason: 'The new edge must be painted',
        );
        expect(await _isInked(tester, harness, addedMid), isTrue);
        expect(
          await _isInked(tester, harness, removedMid),
          isFalse,
          reason: 'A removed edge must not linger in the cached layer',
        );
        controller.cancelNodePresentationDrag(token);
        controller.dispose();
      },
    );
  });
}

/// Whether the pixel at scene point [scene] of the graph is painted red by
/// the recording edge painter.
Future<bool> _isInked(
  WidgetTester tester,
  _Harness harness,
  Offset scene,
) async {
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_shotKey));
  final origin = tester.getTopLeft(_edgesView);
  final local = boundary.globalToLocal(origin + scene);
  late final bool inked;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = (await image.toByteData())!;
    final x = local.dx.round();
    final y = local.dy.round();
    final i = (y * image.width + x) * 4;
    inked = data.getUint8(i) > 200 &&
        data.getUint8(i + 1) < 60 &&
        data.getUint8(i + 2) < 60 &&
        data.getUint8(i + 3) > 200;
    image.dispose();
  });
  return inked;
}

final _shotKey = GlobalKey();

/// Repaint boundaries inside the edges view that contain a custom paint.
Set<RenderObject> _edgeBoundaries(WidgetTester tester) {
  final result = <RenderObject>{};
  bool hasPaint(RenderObject node) {
    var found = node is RenderCustomPaint;
    node.visitChildren((c) => found = hasPaint(c) || found);
    return found;
  }

  void descend(RenderObject node) {
    if (node is RenderRepaintBoundary && hasPaint(node)) result.add(node);
    node.visitChildren(descend);
  }

  descend(tester.renderObject(_edgesView));
  return result;
}

/// Tracks the elements under the edges view across frames: an element that
/// was seen and is gone from the tree counts as deactivated, a newly seen one
/// as inflated.
final class _ElementTracker {
  _ElementTracker(this.tester);

  final WidgetTester tester;
  final _seen = <Element>{};
  var current = <Element>[];
  var inflated = 0;
  var deactivated = 0;

  void observe() {
    final now = <Element>[];
    void descend(Element e) {
      now.add(e);
      e.visitChildren(descend);
    }

    descend(tester.element(_edgesView));
    final nowSet = now.toSet();
    deactivated += _seen.where((e) => !nowSet.contains(e)).length;
    _seen.removeWhere((e) => !nowSet.contains(e));
    for (final e in now) {
      if (_seen.add(e)) inflated++;
    }
    current = now;
  }
}

final _edgesView = find.byWidgetPredicate(
  (w) => w.runtimeType.toString() == 'EdgesView',
);

final class _RecordingEdgePainter
    implements RepaintingEdgePainter<Node<int>, Edge<Node<int>, int>> {
  _RecordingEdgePainter(this.repaint);

  final paints = <int, int>{};

  @override
  final Listenable repaint;

  @override
  void paint(Canvas canvas, Edge<Node<int>, int> edge, Offset a, Offset b) {
    paints.update(edge.data, (c) => c + 1, ifAbsent: () => 1);
    canvas.drawLine(
      a,
      b,
      Paint()
        ..color = const Color(0xFFFF0000)
        ..strokeWidth = 6,
    );
  }
}

final class _Harness {
  final restyle = ChangeNotifier();
  late final _RecordingEdgePainter painter = _RecordingEdgePainter(restyle);
  late final _Controller controller;

  List<int> paintsOf(List<int> ids) => [
        for (final id in ids) painter.paints[id] ?? 0,
      ];
}

Widget _graph(
        _Harness harness, EdgePainter<Node<int>, Edge<Node<int>, int>> p) =>
    MaterialApp(
      home: RepaintBoundary(
        key: _shotKey,
        child: GraphView<Node<int>, Edge<Node<int>, int>>(
          controller: harness.controller,
          canvasSize: const GraphCanvasSize.fixed(Size(500, 500)),
          edgePainter: p,
          layoutAlgorithm: FixedSceneLayoutAlgorithm({
            '1': ScenePoint(x: 100, y: 100),
            '2': ScenePoint(x: 300, y: 300),
            '3': ScenePoint(x: 100, y: 400),
            '4': ScenePoint(x: 400, y: 400),
          }),
          layoutTransitionDuration: const Duration(milliseconds: 300),
          nodeBuilder: (context, node) => SizedBox.square(dimension: node.size),
        ),
      ),
    );

Future<_Harness> _pumpGraph(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final harness = _Harness()..controller = testIntIntGraphController();
  addTearDown(harness.restyle.dispose);

  await tester.pumpWidget(_graph(harness, harness.painter));
  harness.controller.reconcileTopology({_n1, _n2, _n3, _n4}, _edges);
  await settleGraphLayout(tester, harness.controller);
  await tester.pumpAndSettle();
  return harness;
}
