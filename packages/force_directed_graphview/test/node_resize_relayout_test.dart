import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'support/fixed_scene_layout.dart';
import 'support/int_graph_controller.dart';
import 'support/settle_graph_layout.dart';

typedef _Controller = GraphController<Node<int>, Edge<Node<int>, int>>;

// The resized node is the one added last, so replacing it keeps the paint
// order and the node ids of the layer unchanged: only its size differs.
const _small = Node<int>(data: 2, size: 40);
const _large = Node<int>(data: 2, size: 80);
const _other = Node<int>(data: 1, size: 40);

void main() {
  group('A node replaced by one with the same id and a new size', () {
    testWidgets(
      'is laid out at the new size around the same centre',
      (tester) async {
        final controller = await _pumpGraph(tester);
        final finder = find.byKey(const ValueKey('content-2'));
        final sizeBefore = tester.getSize(finder);
        final centreBefore = tester.getCenter(finder);

        _resize(controller, _large);
        await tester.pump();
        await tester.pumpAndSettle();

        expect(
          tester.getSize(finder).width,
          closeTo(sizeBefore.width * 2, 0.01),
          reason: 'The node content must follow the resized scene node',
        );
        expect(
          tester.getSize(finder).height,
          closeTo(sizeBefore.height * 2, 0.01),
        );
        expect(tester.getCenter(finder).dx, closeTo(centreBefore.dx, 0.01));
        expect(tester.getCenter(finder).dy, closeTo(centreBefore.dy, 0.01));
        controller.dispose();
      },
    );

    testWidgets(
      'is laid out at the new size when it shrinks',
      (tester) async {
        final controller = await _pumpGraph(tester, initial: _large);
        final finder = find.byKey(const ValueKey('content-2'));
        final sizeBefore = tester.getSize(finder);

        _resize(controller, _small);
        await tester.pump();
        await tester.pumpAndSettle();

        expect(
          tester.getSize(finder).width,
          closeTo(sizeBefore.width / 2, 0.01),
        );
        controller.dispose();
      },
    );

    testWidgets(
      'has the same drawn, hit-tested and tappable area',
      (tester) async {
        final taps = <Node<int>>[];
        final controller = await _pumpGraph(tester, onTap: taps.add);
        final finder = find.byKey(const ValueKey('content-2'));
        final centre = tester.getCenter(finder);
        final scale = tester.getSize(finder).width / _small.size;

        _resize(controller, _large);
        await tester.pump();
        await tester.pumpAndSettle();

        bool renderHit(Offset point) {
          final result = HitTestResult();
          tester.binding.hitTestInView(result, point, tester.view.viewId);
          final content = tester.renderObject(finder);
          return result.path.any((entry) => entry.target == content);
        }

        // Scene px from the centre along x. The old box reached 20, the new
        // one reaches 40.
        const inside = [10.0, 30.0, 39.0];
        const outside = [41.0, 50.0];
        for (final distance in inside) {
          final point = centre + Offset(distance * scale, 0);
          taps.clear();
          expect(
            tester.getRect(finder).contains(point),
            isTrue,
            reason: 'Drawn bounds must reach $distance scene px',
          );
          expect(
            renderHit(point),
            isTrue,
            reason: 'Render hit test must reach $distance scene px',
          );
          await tester.tapAt(point);
          await tester.pump();
          expect(
            taps,
            [_large],
            reason: 'Scene hit area must reach $distance scene px',
          );
        }
        for (final distance in outside) {
          final point = centre + Offset(distance * scale, 0);
          taps.clear();
          expect(tester.getRect(finder).contains(point), isFalse);
          expect(renderHit(point), isFalse);
          await tester.tapAt(point);
          await tester.pump();
          expect(taps, isEmpty);
        }
        controller.dispose();
      },
    );

    testWidgets(
      'is not laid out again by later drag frames of another node',
      (tester) async {
        final layouts = <int, int>{};
        final controller = await _pumpGraph(tester, layouts: layouts);
        final finder = find.byKey(const ValueKey('content-2'));
        final sizeBefore = tester.getSize(finder);

        _resize(controller, _large);
        await tester.pump();
        await tester.pumpAndSettle();
        expect(
          tester.getSize(finder).width,
          closeTo(sizeBefore.width * 2, 0.01),
          reason: 'The resized node must be laid out at its new size first',
        );

        final token = controller.beginNodePresentationDragForId(
          '1',
          const Offset(100, 100),
        );
        controller.updateNodePresentationDrag(token, const Offset(180, 130));
        await tester.pump();
        final before = Map<int, int>.of(layouts);

        for (var step = 1; step <= 3; step++) {
          controller.updateNodePresentationDrag(
            token,
            Offset(180 + step * 20, 130 + step * 10),
          );
          await tester.pump();
        }

        expect(
          layouts[2],
          before[2],
          reason: 'Drag frames must not lay out the resting resized node',
        );
        controller.cancelNodePresentationDrag(token);
        controller.dispose();
      },
    );
  });
}

void _resize(_Controller controller, Node<int> replacement) {
  controller.reconcileTopology(
    {_other, replacement},
    const {},
    layoutOnTopologyChange: false,
  );
}

Future<_Controller> _pumpGraph(
  WidgetTester tester, {
  Node<int> initial = _small,
  void Function(Node<int>)? onTap,
  Map<int, int>? layouts,
}) async {
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final controller = testIntIntGraphController();
  await tester.pumpWidget(
    MaterialApp(
      home: GraphView<Node<int>, Edge<Node<int>, int>>(
        controller: controller,
        canvasSize: const GraphCanvasSize.fixed(Size(500, 500)),
        layoutAlgorithm: FixedSceneLayoutAlgorithm({
          '1': ScenePoint(x: 100, y: 100),
          '2': ScenePoint(x: 300, y: 300),
        }),
        onNodeTap: onTap,
        // The content fills whatever constraints the node layer gives it.
        nodeBuilder: (context, node) => _LayoutCounting(
          onLayout: () =>
              layouts?.update(node.data, (c) => c + 1, ifAbsent: () => 1),
          child: ColoredBox(
            key: ValueKey('content-${node.data}'),
            color: const Color(0xFF336699),
          ),
        ),
      ),
    ),
  );
  controller.reconcileTopology({_other, initial}, const {});
  await settleGraphLayout(tester, controller);
  await tester.pumpAndSettle();
  return controller;
}

/// Reports every layout call made by the node layer on its child.
class _LayoutCounting extends SingleChildRenderObjectWidget {
  const _LayoutCounting({required this.onLayout, super.child});

  final VoidCallback onLayout;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLayoutCounting(onLayout);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderLayoutCounting renderObject,
  ) =>
      renderObject.onLayout = onLayout;
}

class _RenderLayoutCounting extends RenderProxyBox {
  _RenderLayoutCounting(this.onLayout);

  VoidCallback onLayout;

  @override
  void layout(Constraints constraints, {bool parentUsesSize = false}) {
    onLayout();
    super.layout(constraints, parentUsesSize: parentUsesSize);
  }
}
