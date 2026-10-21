import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:force_directed_graphview/src/widget/graph_layout_view.dart';

import 'support/fixed_scene_layout.dart';
import 'support/int_graph_controller.dart';
import 'support/settle_graph_layout.dart';

typedef _Controller = GraphController<Node<int>, Edge<Node<int>, int>>;

const _smallCount = 4;
const _largeCount = 40;

void main() {
  group('Node layer work does not scale with node count', () {
    testWidgets(
      'a resting scene composites the same number of layers for 4 and 40 nodes',
      (tester) async {
        final small = await _pumpScene(tester, _smallCount);
        final smallLayers = _offsetLayerCount(tester);
        await _disposeScene(tester, small);

        final large = await _pumpScene(tester, _largeCount);
        final largeLayers = _offsetLayerCount(tester);

        expect(
          largeLayers,
          smallLayers,
          reason: 'Stationary nodes must not add compositing layers',
        );
        await _disposeScene(tester, large);
      },
    );

    testWidgets(
      'panning builds, lays out and layers nothing extra, however many nodes',
      (tester) async {
        final small = await _pumpScene(tester, _smallCount);
        final smallLayers = await _panAndCountLayers(tester, small);
        await _disposeScene(tester, small);

        final large = await _pumpScene(tester, _largeCount);
        final buildsBefore = large.totalBuilds;
        final layoutsBefore = large.totalLayouts;
        final largeLayers = await _panAndCountLayers(tester, large);

        expect(large.totalBuilds, buildsBefore, reason: 'node builds on pan');
        expect(
          large.totalLayouts,
          layoutsBefore,
          reason: 'node content layouts on pan',
        );
        expect(
          largeLayers,
          smallLayers,
          reason: 'Layers present during pan frames must not grow with nodes',
        );
        await _disposeScene(tester, large);
      },
    );

    testWidgets(
      'dragging one node adds the same layers whether 4 or 40 nodes exist',
      (tester) async {
        final small = await _pumpScene(tester, _smallCount);
        final smallLayers = await _dragAndCountLayers(tester, small);
        await _disposeScene(tester, small);

        final large = await _pumpScene(tester, _largeCount);
        final buildsBefore = Map<int, int>.of(large.builds);
        final layoutsBefore = Map<int, int>.of(large.layouts);
        final largeLayers = await _dragAndCountLayers(tester, large);

        expect(largeLayers, smallLayers);
        for (var id = 2; id <= _largeCount; id++) {
          expect(
            large.builds[id],
            buildsBefore[id],
            reason: 'Stationary node $id must not rebuild during a drag',
          );
          expect(
            large.layouts[id],
            layoutsBefore[id],
            reason: 'Stationary node $id must not relayout during a drag',
          );
        }
        await _disposeScene(tester, large);
      },
    );
  });

  group('Label and edge work during pan', () {
    testWidgets(
      'panning re-lays-out no label and repaints no edge',
      (tester) async {
        final scene = await _pumpScene(tester, _largeCount, decorated: true);
        expect(scene.edgePaints, greaterThan(0));
        expect(scene.labelBuilds, greaterThanOrEqualTo(_largeCount));
        expect(scene.labelLayoutPasses, greaterThanOrEqualTo(_largeCount));
        final nodeBuilds = scene.totalBuilds;
        final nodeLayouts = scene.totalLayouts;
        final edgePaints = scene.edgePaints;
        final labelBuilds = scene.labelBuilds;
        final labelPasses = scene.labelLayoutPasses;
        final labelContentLayouts = scene.labelContentLayouts;

        await _panAndCountLayers(tester, scene);

        expect(scene.totalBuilds, nodeBuilds, reason: 'node builds on pan');
        expect(scene.totalLayouts, nodeLayouts, reason: 'node layouts on pan');
        expect(scene.edgePaints, edgePaints, reason: 'edge paints on pan');
        expect(scene.labelBuilds, labelBuilds, reason: 'label builds on pan');
        expect(
          scene.labelLayoutPasses,
          labelPasses,
          reason: 'label layout passes on pan',
        );
        expect(
          scene.labelContentLayouts,
          labelContentLayouts,
          reason: 'label content (text) layouts on pan',
        );
        await _disposeScene(tester, scene);
      },
    );

    testWidgets(
      'labels and edges stay attached to nodes after a pan',
      (tester) async {
        final scene = await _pumpScene(tester, _largeCount, decorated: true);
        _viewer(tester).transformationController!.value = Matrix4.identity()
          ..translateByDouble(-30, -20, 0, 1);
        await tester.pump();
        await tester.pump();

        for (var id = 1; id <= _largeCount; id += 7) {
          final label =
              tester.getCenter(find.byKey(ValueKey('label-content-$id')));
          final node = tester.getCenter(find.byKey(ValueKey('node-$id')));
          expect(label.dx, node.dx);
          expect(label.dy, node.dy + _nodeSize / 2 + _labelHeight / 2);
        }
        await _disposeScene(tester, scene);
      },
    );
  });

  group('Node geometry and hit testing without per-node layers', () {
    testWidgets(
      'every node stays at its scene position and tappable after a pan',
      (tester) async {
        final scene = await _pumpScene(tester, _largeCount);

        _viewer(tester).transformationController!.value = Matrix4.identity()
          ..translateByDouble(-40, -25, 0, 1);
        await tester.pump();
        await tester.pump();

        for (var id = 1; id <= _largeCount; id++) {
          expect(
            tester.getCenter(find.byKey(ValueKey('node-$id'))),
            _globalOf(tester, _positionOf(id)),
            reason: 'Node $id is drawn at its scene position after the pan',
          );
          expect(
            tester.getSize(find.byKey(ValueKey('node-$id'))),
            const Size.square(_nodeSize),
          );
        }

        await tester
            .tapAt(tester.getCenter(find.byKey(const ValueKey('node-1'))));
        await tester.pump();
        expect(scene.taps, [1]);
        await _disposeScene(tester, scene);
      },
    );

    testWidgets(
      'a dragged node follows the pointer and settles back without moving others',
      (tester) async {
        final scene = await _pumpScene(tester, _largeCount);
        final controller = scene.controller;
        final others = {
          for (var id = 2; id <= _largeCount; id++)
            id: tester.getCenter(find.byKey(ValueKey('node-$id'))),
        };

        final token = controller.beginNodePresentationDragForId(
          '1',
          _positionOf(1),
        );
        for (final target in const [Offset(160, 120), Offset(300, 180)]) {
          controller.updateNodePresentationDrag(token, target);
          await tester.pump();
          expect(
            tester.getCenter(find.byKey(const ValueKey('node-1'))),
            _globalOf(tester, target),
          );
        }
        for (final entry in others.entries) {
          expect(
            tester.getCenter(find.byKey(ValueKey('node-${entry.key}'))),
            entry.value,
          );
        }

        controller.cancelNodePresentationDrag(token);
        await tester.pump();
        await tester.pump();
        await tester.pumpAndSettle();

        expect(
          tester.getCenter(find.byKey(const ValueKey('node-1'))),
          _globalOf(tester, _positionOf(1)),
          reason: 'A cancelled drag returns the node to its layout position',
        );
        expect(find.byType(_CountingContent), findsNWidgets(_largeCount));
        await _disposeScene(tester, scene);
      },
    );

    testWidgets(
      'a layout transition moves a node between positions and ends on target',
      (tester) async {
        final small = await _pumpScene(tester, _smallCount);
        final restingLayers = _offsetLayerCount(tester);
        await _disposeScene(tester, small);

        final scene = await _pumpScene(tester, _largeCount);
        final controller = scene.controller;
        final start = _globalOf(tester, _positionOf(1));
        const target = Offset(380, 100);

        controller.requestSceneLayout(
          algorithm: FixedSceneLayoutAlgorithm({
            for (var id = 1; id <= _largeCount; id++)
              '$id': ScenePoint(
                x: id == 1 ? target.dx : _positionOf(id).dx,
                y: id == 1 ? target.dy : _positionOf(id).dy,
              ),
          }),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(controller.isLayoutTransitioning, isTrue);
        expect(
          _offsetLayerCount(tester),
          lessThanOrEqualTo(restingLayers + 1),
          reason: 'Only the one animating node may add a layer',
        );
        final mid = tester.getCenter(find.byKey(const ValueKey('node-1')));
        final end = _globalOf(tester, target);
        expect(mid.dx, greaterThan(start.dx));
        expect(mid.dx, lessThan(end.dx));
        expect(
          tester.getCenter(find.byKey(const ValueKey('node-2'))),
          _globalOf(tester, _positionOf(2)),
        );

        await tester.pumpAndSettle();

        expect(controller.isLayoutTransitioning, isFalse);
        expect(tester.getCenter(find.byKey(const ValueKey('node-1'))), end);
        expect(
          _offsetLayerCount(tester),
          restingLayers,
          reason: 'Once settled the layer count is the resting baseline',
        );
        // The default camera puts the target above the viewport, and its
        // centre sits on node 4's edge: tap node 1's own half, on screen.
        _viewer(tester).transformationController!.value = Matrix4.identity();
        await tester.pump();
        await tester.tapAt(_globalOf(tester, target - const Offset(15, 0)));
        await tester.pump();
        expect(scene.taps, [1]);
        await _disposeScene(tester, scene);
      },
    );
  });
}

const _nodeSize = 40.0;

Offset _positionOf(int id) {
  final index = id - 1;
  return Offset(100.0 + (index % 8) * 100, 100.0 + (index ~/ 8) * 100);
}

final class _Scene {
  _Scene(this.controller);

  final _Controller controller;
  final builds = <int, int>{};
  final layouts = <int, int>{};
  final taps = <int>[];
  int edgePaints = 0;
  int labelBuilds = 0;
  int labelLayoutPasses = 0;
  int labelContentLayouts = 0;

  int get totalBuilds => builds.values.fold(0, (a, b) => a + b);
  int get totalLayouts => layouts.values.fold(0, (a, b) => a + b);
}

Future<_Scene> _pumpScene(
  WidgetTester tester,
  int count, {
  bool decorated = false,
}) async {
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final controller = testIntIntGraphController();
  final scene = _Scene(controller);
  final nodes = [
    for (var id = 1; id <= count; id++) Node<int>(data: id, size: _nodeSize),
  ];

  await tester.pumpWidget(
    MaterialApp(
      home: GraphView<Node<int>, Edge<Node<int>, int>>(
        controller: controller,
        canvasSize: const GraphCanvasSize.fixed(Size(1000, 1000)),
        layoutAlgorithm: FixedSceneLayoutAlgorithm({
          for (var id = 1; id <= count; id++)
            '$id': ScenePoint(x: _positionOf(id).dx, y: _positionOf(id).dy),
        }),
        layoutTransitionDuration: const Duration(milliseconds: 300),
        onNodeTap: (node) => scene.taps.add(node.data),
        edgePainter:
            decorated ? _CountingEdgePainter(scene) : const LineEdgePainter(),
        labelBuilder: decorated ? _CountingLabelBuilder(scene) : null,
        nodeBuilder: (context, node) {
          scene.builds.update(node.data, (c) => c + 1, ifAbsent: () => 1);
          return _CountingContent(
            key: ValueKey('node-${node.data}'),
            size: node.size,
            onLayout: () => scene.layouts
                .update(node.data, (c) => c + 1, ifAbsent: () => 1),
          );
        },
      ),
    ),
  );
  final edges = <Edge<Node<int>, int>>{
    if (decorated)
      for (var i = 0; i < count - 1; i++)
        Edge<Node<int>, int>(
          source: nodes[i],
          destination: nodes[i + 1],
          data: i + 1,
        ),
  };
  controller.reconcileTopology({...nodes}, edges);
  await settleGraphLayout(tester, controller);
  await tester.pumpAndSettle();
  return scene;
}

Future<void> _disposeScene(WidgetTester tester, _Scene scene) async {
  await tester.pumpWidget(const SizedBox.shrink());
  scene.controller.dispose();
}

InteractiveViewer _viewer(WidgetTester tester) =>
    tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));

int _offsetLayerCount(WidgetTester tester) =>
    tester.layers.whereType<OffsetLayer>().length;

/// Layers present across several consecutive pan frames (the maximum seen).
Future<int> _panAndCountLayers(WidgetTester tester, _Scene scene) async {
  var most = 0;
  for (var step = 1; step <= 4; step++) {
    _viewer(tester).transformationController!.value = Matrix4.identity()
      ..translateByDouble(-12.0 * step, -7.0 * step, 0, 1);
    await tester.pump();
    final count = _offsetLayerCount(tester);
    if (count > most) {
      most = count;
    }
  }
  return most;
}

/// Layers present across several frames of dragging node 1 (the maximum seen).
Future<int> _dragAndCountLayers(WidgetTester tester, _Scene scene) async {
  final controller = scene.controller;
  final token = controller.beginNodePresentationDragForId(
    '1',
    _positionOf(1),
  );
  var most = 0;
  for (var step = 1; step <= 4; step++) {
    controller.updateNodePresentationDrag(
      token,
      _positionOf(1) + Offset(30.0 * step, 15.0 * step),
    );
    await tester.pump();
    final count = _offsetLayerCount(tester);
    if (count > most) {
      most = count;
    }
  }
  controller.cancelNodePresentationDrag(token);
  await tester.pump();
  await tester.pump();
  return most;
}

Offset _globalOf(WidgetTester tester, Offset scenePoint) {
  final graphBox = tester.renderObject<RenderBox>(find.byType(GraphLayoutView));
  return graphBox.localToGlobal(scenePoint);
}

/// Node content that reports every layout pass and paints a visible square.
class _CountingContent extends LeafRenderObjectWidget {
  const _CountingContent({
    required this.size,
    required this.onLayout,
    super.key,
  });

  final double size;
  final VoidCallback onLayout;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCountingContent(size, onLayout);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderCountingContent renderObject,
  ) {
    renderObject
      ..side = size
      ..onLayout = onLayout;
  }
}

class _RenderCountingContent extends RenderBox {
  _RenderCountingContent(this._side, this.onLayout);

  double _side;
  VoidCallback onLayout;

  set side(double value) {
    if (value != _side) {
      _side = value;
      markNeedsLayout();
    }
  }

  @override
  void performLayout() {
    onLayout();
    size = constraints.constrain(Size.square(_side));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    context.canvas.drawRect(
      offset & size,
      Paint()..color = const Color(0xFF3366CC),
    );
  }
}

const _labelHeight = 20.0;

final class _CountingEdgePainter
    implements EdgePainter<Node<int>, Edge<Node<int>, int>> {
  _CountingEdgePainter(this._scene);

  final _Scene _scene;

  @override
  void paint(
    Canvas canvas,
    Edge<Node<int>, int> edge,
    Offset sourcePosition,
    Offset destinationPosition,
  ) {
    _scene.edgePaints++;
    canvas.drawLine(sourcePosition, destinationPosition, Paint());
  }
}

final class _CountingLabelBuilder implements LabelBuilder<Node<int>> {
  _CountingLabelBuilder(this._scene);

  final _Scene _scene;

  @override
  Widget build(BuildContext context, Node<int> node) {
    _scene.labelBuilds++;
    return _CountingContent(
      key: ValueKey('label-content-${node.data}'),
      size: _labelHeight,
      onLayout: () => _scene.labelContentLayouts++,
    );
  }

  @override
  void performLayout(
    Size size,
    Node<int> node,
    double nodeSize,
    Offset nodePosition,
    Size Function(BoxConstraints constraints) layoutChild,
    void Function(Offset offset) positionChild,
  ) {
    _scene.labelLayoutPasses++;
    final labelSize = layoutChild(BoxConstraints.tight(
      const Size.square(_labelHeight),
    ));
    positionChild(
      nodePosition + Offset(-labelSize.width / 2, nodeSize / 2),
    );
  }
}
