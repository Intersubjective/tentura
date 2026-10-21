import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'support/fixed_scene_layout.dart';
import 'support/int_graph_controller.dart';
import 'support/settle_graph_layout.dart';

typedef _Controller = GraphController<Node<int>, Edge<Node<int>, int>>;

void main() {
  group('Resting nodes share one layer apart from the dragged node', () {
    testWidgets(
      'dragging a node repaints no resting node',
      (tester) async {
        final harness = await _pumpGraph(tester);
        final controller = harness.controller;

        final token = controller.beginNodePresentationDragForId(
          '1',
          const Offset(100, 100),
        );
        controller.updateNodePresentationDrag(token, const Offset(180, 130));
        await tester.pump();
        final restingBefore = _paints(harness, const [2, 3, 4]);
        final draggedBefore = harness.paints[1]!;
        final decoratedBefore =
            _typePaints(harness, 'RenderDecoratedBox', const [2, 3, 4]);
        final paragraphsBefore =
            _typePaints(harness, 'RenderParagraph', const [2, 3, 4]);

        for (var step = 1; step <= 3; step++) {
          controller.updateNodePresentationDrag(
            token,
            Offset(180 + step * 20, 130 + step * 10),
          );
          await tester.pump();
        }

        expect(
          _paints(harness, const [2, 3, 4]),
          restingBefore,
          reason: 'Resting nodes must not be re-recorded on drag frames',
        );
        expect(
          _typePaints(harness, 'RenderDecoratedBox', const [2, 3, 4]),
          decoratedBefore,
          reason: 'Resting decorated boxes must not repaint on drag frames',
        );
        expect(
          _typePaints(harness, 'RenderParagraph', const [2, 3, 4]),
          paragraphsBefore,
          reason: 'Resting text must not repaint on drag frames',
        );
        expect(
          harness.paints[1],
          greaterThan(draggedBefore),
          reason: 'The dragged node keeps painting every frame',
        );
        controller.cancelNodePresentationDrag(token);
        controller.dispose();
      },
    );

    testWidgets(
      'resting nodes are not repainted by the frames after a drop',
      (tester) async {
        final harness = await _pumpGraph(tester);
        final controller = harness.controller;

        final token = controller.beginNodePresentationDragForId(
          '1',
          const Offset(100, 100),
        );
        controller.updateNodePresentationDrag(token, const Offset(200, 140));
        await tester.pump();
        controller.cancelNodePresentationDrag(token);
        await tester.pump();
        await tester.pump();
        await tester.pumpAndSettle();
        final restingAfterDrop = _paints(harness, const [2, 3, 4]);

        await tester.pump(const Duration(milliseconds: 16));
        await tester.pumpAndSettle();

        expect(_paints(harness, const [2, 3, 4]), restingAfterDrop);
        controller.dispose();
      },
    );

    testWidgets(
      'moving a resting node repaints the shared layer',
      (tester) async {
        final harness = await _pumpGraph(tester);
        final controller = harness.controller;
        final before = _paints(harness, const [2, 3, 4]);

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
        await tester.pumpAndSettle();

        expect(
          _paints(harness, const [2, 3, 4]),
          isNot(before),
          reason: 'A changed resting position must still reach the screen',
        );
        controller.dispose();
      },
    );
  });

  group('Layer structure and layout work', () {
    testWidgets(
      'resting nodes share one repaint boundary',
      (tester) async {
        final harness = await _pumpGraph(tester);

        final shared = _boundaries(tester, 1).first;
        for (final id in const [2, 3, 4]) {
          expect(_boundaries(tester, id).first, same(shared));
        }
        harness.controller.dispose();
      },
    );

    testWidgets(
      'the dragged node has its own repaint boundary apart from the shared one',
      (tester) async {
        final harness = await _pumpGraph(tester);
        final controller = harness.controller;
        final sharedBefore = _boundaries(tester, 2).first;

        final token = controller.beginNodePresentationDragForId(
          '1',
          const Offset(100, 100),
        );
        controller.updateNodePresentationDrag(token, const Offset(200, 140));
        await tester.pump();

        final dragged = _boundaries(tester, 1);
        final resting = _boundaries(tester, 2);
        expect(
          dragged.first,
          isNot(same(resting.first)),
          reason: 'The dragged node must paint into a layer of its own',
        );
        expect(
          resting.first,
          same(sharedBefore),
          reason: 'Resting nodes keep one shared layer through a grab',
        );
        for (final id in const [3, 4]) {
          expect(_boundaries(tester, id).first, same(resting.first));
        }

        controller.cancelNodePresentationDrag(token);
        await tester.pump();
        await tester.pump();
        controller.dispose();
      },
    );

    testWidgets(
      'nodes moving in a layout transition stay in the shared layer',
      (tester) async {
        final harness = await _pumpGraph(tester);
        final controller = harness.controller;

        controller.requestSceneLayout(
          algorithm: FixedSceneLayoutAlgorithm({
            '1': ScenePoint(x: 380, y: 100),
            '2': ScenePoint(x: 300, y: 120),
            '3': ScenePoint(x: 100, y: 400),
            '4': ScenePoint(x: 400, y: 400),
          }),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(controller.isLayoutTransitioning, isTrue);

        final shared = _boundaries(tester, 3).first;
        for (final id in const [1, 2, 4]) {
          expect(_boundaries(tester, id).first, same(shared));
        }
        await tester.pumpAndSettle();
        controller.dispose();
      },
    );

    testWidgets(
      'dragging a node does not lay out the resting nodes again',
      (tester) async {
        final harness = await _pumpGraph(tester);
        final controller = harness.controller;

        final token = controller.beginNodePresentationDragForId(
          '1',
          const Offset(100, 100),
        );
        controller.updateNodePresentationDrag(token, const Offset(180, 130));
        await tester.pump();
        final before = _layouts(harness, const [2, 3, 4]);

        for (var step = 1; step <= 3; step++) {
          controller.updateNodePresentationDrag(
            token,
            Offset(180 + step * 20, 130 + step * 10),
          );
          await tester.pump();
        }

        expect(_layouts(harness, const [2, 3, 4]), before);
        controller.cancelNodePresentationDrag(token);
        controller.dispose();
      },
    );

    testWidgets(
      'a changed resting position lays out the resting nodes',
      (tester) async {
        final harness = await _pumpGraph(tester);
        final controller = harness.controller;
        final before = _layouts(harness, const [2]);

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
        await tester.pumpAndSettle();

        expect(_layouts(harness, const [2])[0], greaterThan(before[0]));
        controller.dispose();
      },
    );
  });

  group('Dedicated resting layer', () {
    testWidgets(
      'resting nodes paint into a boundary of their own below the scene layer',
      (tester) async {
        final harness = await _pumpGraph(tester);

        for (final id in const [1, 2, 3, 4]) {
          expect(
            _boundaries(tester, id).length,
            greaterThanOrEqualTo(2),
            reason: 'Node $id needs the shared resting-node boundary in '
                'addition to the scene-wide one',
          );
        }
        harness.controller.dispose();
      },
    );
  });

  group('Behaviour across grab and drop', () {
    testWidgets(
      'the dragged node keeps exactly one semantics node through grab and drop',
      (tester) async {
        final handle = tester.ensureSemantics();
        final harness = await _pumpGraph(tester);
        final controller = harness.controller;
        for (final id in const [1, 2, 3, 4]) {
          expect(_nodeSemantics(id), findsOneWidget);
        }

        final token = controller.beginNodePresentationDragForId(
          '1',
          const Offset(100, 100),
        );
        controller.updateNodePresentationDrag(token, const Offset(200, 140));
        await tester.pump();
        for (final id in const [1, 2, 3, 4]) {
          expect(
            _nodeSemantics(id),
            findsOneWidget,
            reason: 'node-$id lost its semantics while node 1 is dragged',
          );
        }

        controller.cancelNodePresentationDrag(token);
        await tester.pump();
        await tester.pump();
        for (final id in const [1, 2, 3, 4]) {
          expect(_nodeSemantics(id), findsOneWidget);
        }
        handle.dispose();
        controller.dispose();
      },
    );

    testWidgets(
      'a dragged node lying over a resting node is the topmost hit',
      (tester) async {
        final harness = await _pumpGraph(tester);
        final controller = harness.controller;

        final token = controller.beginNodePresentationDragForId(
          '1',
          const Offset(100, 100),
        );
        controller.updateNodePresentationDrag(token, const Offset(300, 300));
        await tester.pump();

        final point = tester.getCenter(find.byKey(const ValueKey('box-2')));
        final result = HitTestResult();
        tester.binding.hitTestInView(result, point, tester.view.viewId);
        final firstBox = result.path
            .map((entry) => entry.target)
            .whereType<_RenderCountingBox>()
            .first;

        expect(
          firstBox,
          same(tester.renderObject(find.byKey(const ValueKey('box-1')))),
          reason: 'The node being dragged must stack above the nodes it '
              'passes over',
        );
        controller.cancelNodePresentationDrag(token);
        await tester.pump();
        await tester.pump();
        controller.dispose();
      },
    );
  });

  group('Node subtrees are not re-parented', () {
    testWidgets(
      'a layout transition deactivates no node subtree',
      (tester) async {
        final harness = await _pumpGraph(tester);
        final controller = harness.controller;
        final created = Map<int, int>.of(harness.created);

        controller.requestSceneLayout(
          algorithm: FixedSceneLayoutAlgorithm({
            '1': ScenePoint(x: 380, y: 100),
            '2': ScenePoint(x: 300, y: 120),
            '3': ScenePoint(x: 100, y: 400),
            '4': ScenePoint(x: 400, y: 400),
          }),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(controller.isLayoutTransitioning, isTrue);
        await tester.pumpAndSettle();

        expect(
          harness.deactivated,
          isEmpty,
          reason: 'Moving transition nodes stay in the shared layer, so no '
              'subtree is deactivated and re-inflated through a GlobalKey',
        );
        expect(harness.created, created);
        controller.dispose();
      },
    );

    testWidgets(
      'a drag re-parents only the dragged node, once per grab and drop',
      (tester) async {
        final harness = await _pumpGraph(tester);
        final controller = harness.controller;

        final token = controller.beginNodePresentationDragForId(
          '1',
          const Offset(100, 100),
        );
        controller.updateNodePresentationDrag(token, const Offset(200, 140));
        await tester.pump();
        controller.updateNodePresentationDrag(token, const Offset(240, 160));
        await tester.pump();
        controller.cancelNodePresentationDrag(token);
        await tester.pump();
        await tester.pump();
        await tester.pumpAndSettle();

        expect(harness.deactivated.keys.toSet(), {1});
        expect(harness.deactivated[1], lessThanOrEqualTo(2));
        expect(harness.created, {1: 1, 2: 1, 3: 1, 4: 1});
        controller.dispose();
      },
    );

    testWidgets(
      'the dragged node keeps focus across grab and drop',
      (tester) async {
        final harness = await _pumpGraph(tester);
        final controller = harness.controller;
        final focus = harness.focusNode;
        focus.requestFocus();
        await tester.pump();
        expect(focus.hasPrimaryFocus, isTrue);

        final token = controller.beginNodePresentationDragForId(
          '1',
          const Offset(100, 100),
        );
        controller.updateNodePresentationDrag(token, const Offset(200, 140));
        await tester.pump();
        expect(focus.hasPrimaryFocus, isTrue, reason: 'lost on grab');

        controller.cancelNodePresentationDrag(token);
        await tester.pump();
        await tester.pump();
        expect(focus.hasPrimaryFocus, isTrue, reason: 'lost on drop');
        controller.dispose();
      },
    );
  });
}

const _nodes = [
  Node<int>(data: 1, size: 40),
  Node<int>(data: 2, size: 40),
  Node<int>(data: 3, size: 40),
  Node<int>(data: 4, size: 40),
];

/// The semantics node of node [id]; its label is merged with the node text.
Finder _nodeSemantics(int id) => find.bySemanticsLabel(RegExp('^node-$id\\n'));

List<int> _layouts(_Harness harness, List<int> ids) =>
    [for (final id in ids) harness.parentLayouts[id]!];

/// Repaint-boundary render objects between node [data]'s content and the
/// graph view's render object, nearest first.
List<RenderObject> _boundaries(WidgetTester tester, int data) {
  final result = <RenderObject>[];
  final graph = tester
      .renderObject(find.byType(GraphView<Node<int>, Edge<Node<int>, int>>));
  RenderObject? node = tester.renderObject(find.byKey(ValueKey('box-$data')));
  while (node != null && node != graph) {
    if (node.isRepaintBoundary) {
      result.add(node);
    }
    node = node.parent;
  }
  return result;
}

/// Paint counts of the framework render object type [type] per node.
List<int> _typePaints(_Harness harness, String type, List<int> ids) =>
    [for (final id in ids) harness.typePaints[type]![id]!];

List<int> _paints(_Harness harness, List<int> ids) =>
    [for (final id in ids) harness.paints[id]!];

final class _Harness {
  final paints = <int, int>{};
  final typePaints = <String, Map<int, int>>{};
  final parentLayouts = <int, int>{};
  final created = <int, int>{};
  final deactivated = <int, int>{};
  final focusNode = FocusNode();
  late final _Controller controller;
}

Future<_Harness> _pumpGraph(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final harness = _Harness();
  addTearDown(harness.focusNode.dispose);
  harness.controller = testIntIntGraphController();

  await tester.pumpWidget(
    MaterialApp(
      home: GraphView<Node<int>, Edge<Node<int>, int>>(
        controller: harness.controller,
        canvasSize: const GraphCanvasSize.fixed(Size(500, 500)),
        layoutAlgorithm: FixedSceneLayoutAlgorithm({
          '1': ScenePoint(x: 100, y: 100),
          '2': ScenePoint(x: 300, y: 300),
          '3': ScenePoint(x: 100, y: 400),
          '4': ScenePoint(x: 400, y: 400),
        }),
        layoutTransitionDuration: const Duration(milliseconds: 300),
        nodeBuilder: (context, node) => _Content(
          key: ValueKey('node-${node.data}'),
          data: node.data,
          size: node.size,
          harness: harness,
        ),
      ),
    ),
  );
  harness.controller.reconcileTopology({..._nodes}, const {});
  await settleGraphLayout(tester, harness.controller);
  await tester.pumpAndSettle();
  harness.deactivated.clear();
  return harness;
}

class _Content extends StatefulWidget {
  const _Content({
    required this.data,
    required this.size,
    required this.harness,
    super.key,
  });

  final int data;
  final double size;
  final _Harness harness;

  @override
  State<_Content> createState() => _ContentState();
}

class _ContentState extends State<_Content> {
  @override
  void initState() {
    super.initState();
    widget.harness.created.update(widget.data, (c) => c + 1, ifAbsent: () => 1);
  }

  @override
  void deactivate() {
    widget.harness.deactivated
        .update(widget.data, (c) => c + 1, ifAbsent: () => 1);
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) {
    void count(String type) => widget.harness.typePaints
        .putIfAbsent(type, () => {})
        .update(widget.data, (c) => c + 1, ifAbsent: () => 1);
    final box = _CountingBox(
      key: ValueKey('box-${widget.data}'),
      size: widget.size,
      onPaint: () => widget.harness.paints
          .update(widget.data, (c) => c + 1, ifAbsent: () => 1),
    );
    final inner = Semantics(
      container: true,
      label: 'node-${widget.data}',
      child: SizedBox.square(
        dimension: widget.size,
        child: Stack(
          children: [
            Positioned.fill(child: box),
            _CountingParagraph(
              text: '${widget.data}',
              onPaint: () => count('RenderParagraph'),
            ),
          ],
        ),
      ),
    );
    // The counting decorated box stays outermost so that its layout count is
    // the node layer's layout pass count for this node.
    return _CountingDecorated(
      onPaint: () => count('RenderDecoratedBox'),
      onParentLayout: () => widget.harness.parentLayouts
          .update(widget.data, (c) => c + 1, ifAbsent: () => 1),
      child: widget.data == 1
          ? Focus(focusNode: widget.harness.focusNode, child: inner)
          : inner,
    );
  }
}

class _CountingDecorated extends SingleChildRenderObjectWidget {
  const _CountingDecorated({
    required this.onPaint,
    required this.onParentLayout,
    super.child,
  });

  final VoidCallback onPaint;
  final VoidCallback onParentLayout;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCountingDecorated(onPaint, onParentLayout);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderCountingDecorated renderObject,
  ) =>
      renderObject
        ..onPaint = onPaint
        ..onParentLayout = onParentLayout;
}

class _RenderCountingDecorated extends RenderDecoratedBox {
  _RenderCountingDecorated(this.onPaint, this.onParentLayout)
      : super(decoration: const BoxDecoration(color: Color(0xFF336699)));

  VoidCallback onPaint;
  VoidCallback onParentLayout;

  /// Called by the node layer, so this counts the layer's layout passes.
  @override
  void layout(Constraints constraints, {bool parentUsesSize = false}) {
    onParentLayout();
    super.layout(constraints, parentUsesSize: parentUsesSize);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    onPaint();
    super.paint(context, offset);
  }
}

class _CountingParagraph extends LeafRenderObjectWidget {
  const _CountingParagraph({required this.text, required this.onPaint});

  final String text;
  final VoidCallback onPaint;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCountingParagraph(
        TextSpan(text: text, style: const TextStyle(fontSize: 10)),
        onPaint,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderCountingParagraph renderObject,
  ) =>
      renderObject.onPaint = onPaint;
}

class _RenderCountingParagraph extends RenderParagraph {
  _RenderCountingParagraph(super.text, this.onPaint)
      : super(textDirection: TextDirection.ltr);

  VoidCallback onPaint;

  @override
  void paint(PaintingContext context, Offset offset) {
    onPaint();
    super.paint(context, offset);
  }
}

/// Node content that reports every paint.
class _CountingBox extends LeafRenderObjectWidget {
  const _CountingBox({
    required this.size,
    required this.onPaint,
    super.key,
  });

  final double size;
  final VoidCallback onPaint;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCountingBox(size, onPaint);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderCountingBox renderObject,
  ) {
    renderObject.onPaint = onPaint;
  }
}

class _RenderCountingBox extends RenderBox {
  _RenderCountingBox(this._size, this.onPaint);

  final double _size;
  VoidCallback onPaint;

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void performLayout() => size = constraints.constrain(Size.square(_size));

  @override
  void paint(PaintingContext context, Offset offset) {
    onPaint();
    context.canvas.drawRect(offset & size, Paint());
  }
}
