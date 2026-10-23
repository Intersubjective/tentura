import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:force_directed_graphview/src/widget/graph_layout_view.dart';

import 'support/fixed_scene_layout.dart';
import 'support/int_graph_controller.dart';
import 'support/settle_graph_layout.dart';

/// #464 / #615: zooming or panning the graph while it is still empty (no
/// nodes yet, e.g. while it loads) must not trip InteractiveViewer's
/// "child must have nonzero dimensions" assertion.

const _viewport = Size(800, 600);
const _canvas = Size(4096, 4096);

Future<GraphController<Node<int>, Edge<Node<int>, int>>> _pumpEmpty(
  WidgetTester tester, {
  GraphCanvasSize canvasSize = const GraphCanvasSize.fixed(_canvas),
}) async {
  tester.view.physicalSize = _viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final controller = testIntIntGraphController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: GraphView<Node<int>, Edge<Node<int>, int>>(
        controller: controller,
        canvasSize: canvasSize,
        minScale: 0.1,
        maxScale: 3,
        layoutAlgorithm: FixedSceneLayoutAlgorithm({
          '1': ScenePoint(x: _canvas.width / 2, y: _canvas.height / 2),
        }),
        nodeBuilder: (context, node) =>
            SizedBox(width: node.size, height: node.size),
      ),
    ),
  );
  await tester.pump();
  return controller;
}

Future<void> _wheel(WidgetTester tester, Offset delta) async {
  final at = tester.getCenter(find.byType(InteractiveViewer));
  final pointer = TestPointer(5, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(pointer.hover(at));
  await tester.sendEventToBinding(pointer.scroll(delta));
  await tester.pump();
}

Size _sceneSize(WidgetTester tester) =>
    tester.renderObject<RenderBox>(find.byType(GraphLayoutView)).size;

void main() {
  testWidgets('wheel zoom on an empty graph does not assert', (tester) async {
    final controller = await _pumpEmpty(tester);
    expect(controller.canLayout, isFalse);

    await _wheel(tester, const Offset(0, -40));

    expect(tester.takeException(), isNull);
    // A normal zoom step, not a jump to a clamp.
    expect(controller.currentScale, greaterThan(1));
    expect(controller.currentScale, lessThan(1.5));

    await _wheel(tester, const Offset(0, 80));
    expect(tester.takeException(), isNull);
    expect(controller.currentScale, lessThan(1));
  });

  testWidgets('panning an empty graph does not assert', (tester) async {
    await _pumpEmpty(tester);

    await tester.drag(find.byType(InteractiveViewer), const Offset(-120, -80));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'wheel zoom on an empty graph whose canvas resolves to zero size does not '
    'assert',
    (tester) async {
      // A proportional canvas has no area until it has nodes.
      final controller = await _pumpEmpty(
        tester,
        canvasSize: const GraphCanvasSize.proportional(),
      );

      await _wheel(tester, const Offset(0, -40));

      expect(tester.takeException(), isNull);
      expect(controller.currentScale, greaterThan(1));
      expect(controller.currentScale, lessThan(1.5));
    },
  );

  testWidgets(
    'a zoom made while empty is kept and the scene keeps the canvas size once '
    'the graph arrives',
    (tester) async {
      final controller = await _pumpEmpty(tester);
      // The empty scene already spans the canvas, so the camera bounds do not
      // jump when the first node lands.
      expect(_sceneSize(tester), _canvas);

      await _wheel(tester, const Offset(0, -40));
      expect(tester.takeException(), isNull);
      final zoomed = controller.currentScale;

      const node = Node<int>(data: 1, size: 40);
      controller.reconcileTopology({node}, {});
      await settleGraphLayout(tester, controller);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(controller.canLayout, isTrue);
      expect(_sceneSize(tester), _canvas);
      expect(controller.currentScale, moreOrLessEquals(zoomed));

      await _wheel(tester, const Offset(0, -40));
      expect(tester.takeException(), isNull);
      expect(controller.currentScale, greaterThan(zoomed));
    },
  );
}
