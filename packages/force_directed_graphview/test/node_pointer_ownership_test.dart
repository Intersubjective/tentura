import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:force_directed_graphview/src/widget/graph_layout_view.dart';

import 'support/fixed_scene_layout.dart';
import 'support/int_graph_controller.dart';
import 'support/settle_graph_layout.dart';

const _bottom = Node<int>(data: 3, size: 100);
const _far = Node<int>(data: 4, size: 100);

void main() {
  group('node pointer ownership', () {
    for (final kind in [
      PointerDeviceKind.mouse,
      PointerDeviceKind.touch,
      PointerDeviceKind.stylus,
    ]) {
      testWidgets('${kind.name} press and release on a node taps it',
          (tester) async {
        final h = await _pump(tester);
        final gesture = await tester.createGesture(kind: kind);
        await gesture.down(h.centre(_bottom));
        await gesture.up();
        await tester.pump();

        expect(h.taps, [_bottom]);
        expect(h.dragStarts, isEmpty);
        h.controller.dispose();
      });

      testWidgets(
          '${kind.name} drag from a node moves the node and fixes the camera',
          (tester) async {
        final h = await _pump(tester);
        final before = h.camera();
        final gesture = await tester.createGesture(kind: kind);
        await gesture.down(h.centre(_bottom));
        for (var i = 0; i < 5; i++) {
          await gesture.moveBy(const Offset(12, 4));
          expect(h.camera(), orderedEquals(before));
        }
        await tester.pump();

        expect(h.dragStarts, [_bottom]);
        expect(h.controller.isCameraGated, isTrue);
        expect(h.camera(), orderedEquals(before));
        expect(h.dragPositions, isNotEmpty);
        final moved = h.dragPositions.last - h.dragStartPosition!;
        // 60x20 screen px at 1.5x zoom is 40x13.3 scene px, less touch slop.
        expect(moved.dx, greaterThan(20));
        expect(moved.dy, greaterThan(5));

        await gesture.up();
        await tester.pump();
        expect(h.taps, isEmpty);
        expect(h.dragEnds, 1);
        expect(h.controller.isCameraGated, isFalse);
        expect(h.camera(), orderedEquals(before));
        h.controller.dispose();
      });
    }

    const ownerKinds = [
      PointerDeviceKind.mouse,
      PointerDeviceKind.touch,
      PointerDeviceKind.stylus,
    ];

    testWidgets('pinch on empty canvas zooms the camera', (tester) async {
      final h = await _pump(tester);
      final before = h.controller.currentScale;
      final a = await tester.createGesture();
      final b = await tester.createGesture();
      final origin = h.sceneToGlobal(const Offset(250, 80));
      await a.down(origin);
      await b.down(origin + const Offset(40, 0));
      await a.moveBy(const Offset(-30, 0));
      await b.moveBy(const Offset(30, 0));
      await a.moveBy(const Offset(-30, 0));
      await b.moveBy(const Offset(30, 0));
      await tester.pump();

      expect(h.controller.currentScale, greaterThan(before));
      expect(h.dragStarts, isEmpty);
      expect(h.controller.isCameraGated, isFalse);
      await a.up();
      await b.up();
      h.controller.dispose();
    });

    for (final primary in ownerKinds) {
      testWidgets(
          'extra touch on empty canvas during a ${primary.name} node drag '
          'is ignored', (tester) async {
        final h = await _pump(tester);
        final before = h.camera();
        final first = await tester.createGesture(kind: primary);
        await first.down(h.centre(_bottom));
        await first.moveBy(const Offset(30, 0));
        await tester.pump();
        final drags = h.dragUpdates;

        final extra = await tester.createGesture(
          pointer: 77,
        );
        await extra.down(h.sceneToGlobal(const Offset(250, 80)));
        await extra.moveBy(const Offset(40, 0));
        await extra.moveBy(const Offset(40, 30));
        await tester.pump();

        expect(h.camera(), orderedEquals(before));
        expect(h.controller.isCameraGated, isTrue);
        expect(h.dragStarts, [_bottom]);

        await first.moveBy(const Offset(20, 0));
        await tester.pump();
        expect(h.dragUpdates, greaterThan(drags));
        expect(h.camera(), orderedEquals(before));

        await extra.up();
        await first.up();
        await tester.pump();
        expect(h.dragEnds, 1);
        expect(h.dragCancels, 0);
        expect(h.controller.isCameraGated, isFalse);
        h.controller.dispose();
      });
    }

    for (final primary in ownerKinds) {
      testWidgets(
          'extra touch keeps the camera fixed after the ${primary.name} '
          'owner lifts', (tester) async {
        final h = await _pump(tester);
        final before = h.camera();
        final owner = await tester.createGesture(kind: primary);
        await owner.down(h.centre(_bottom));
        await owner.moveBy(const Offset(30, 0));
        await tester.pump();
        final extra = await tester.createGesture(
          pointer: 77,
        );
        await extra.down(h.sceneToGlobal(const Offset(250, 80)));
        await owner.up();
        await extra.moveBy(const Offset(60, 20));
        await extra.moveBy(const Offset(60, 20));
        await tester.pump();

        expect(h.camera(), orderedEquals(before));
        await extra.up();
        await tester.pump();
        expect(h.controller.isCameraGated, isFalse);
        h.controller.dispose();
      });
    }

    testWidgets('two extra touches during a node drag cannot pinch the camera',
        (tester) async {
      final h = await _pump(tester);
      final before = h.camera();
      final owner = await tester.createGesture();
      await owner.down(h.centre(_bottom));
      await owner.moveBy(const Offset(30, 0));
      await tester.pump();
      final extraA = await tester.createGesture(
        pointer: 77,
      );
      final extraB = await tester.createGesture(
        pointer: 78,
      );
      final spot = h.sceneToGlobal(const Offset(250, 80));
      await extraA.down(spot);
      await extraB.down(spot + const Offset(40, 0));
      await extraA.moveBy(const Offset(-30, 0));
      await extraB.moveBy(const Offset(30, 0));
      await extraA.moveBy(const Offset(-30, 0));
      await extraB.moveBy(const Offset(30, 0));
      await tester.pump();

      expect(h.camera(), orderedEquals(before));
      expect(h.controller.isCameraGated, isTrue);

      await extraA.up();
      await extraB.up();
      await owner.up();
      await tester.pump();
      expect(h.dragEnds, 1);
      expect(h.controller.isCameraGated, isFalse);
      h.controller.dispose();
    });
  });
}

class _Harness {
  _Harness(this.tester, this.controller);

  final WidgetTester tester;
  final GraphController<Node<int>, Edge<Node<int>, int>> controller;
  final List<Node<int>> taps = [];
  final List<Node<int>> dragStarts = [];
  Offset? dragStartPosition;
  final List<Offset> dragPositions = [];
  int dragUpdates = 0;
  int dragEnds = 0;
  int dragCancels = 0;

  List<double> camera() => tester
      .widget<InteractiveViewer>(find.byType(InteractiveViewer))
      .transformationController!
      .value
      .storage
      .toList();

  Offset sceneToGlobal(Offset scene) => tester
      .renderObject<RenderBox>(find.byType(GraphLayoutView))
      .localToGlobal(scene);

  Offset centre(Node<int> node) =>
      sceneToGlobal(testNodePosition(controller, node));
}

Future<_Harness> _pump(WidgetTester tester) async {
  final controller = testIntIntGraphController();
  final h = _Harness(tester, controller);
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
          layoutAlgorithm: FixedSceneLayoutAlgorithm({
            '3': ScenePoint(x: 150, y: 250),
            '4': ScenePoint(x: 400, y: 400),
          }),
          onNodeTap: h.taps.add,
          onNodeDragStart: (node, position) {
            h.dragStarts.add(node);
            h.dragStartPosition = position;
          },
          onNodeDragUpdate: (_, position) {
            h.dragUpdates++;
            h.dragPositions.add(position);
          },
          onNodeDragEnd: (_, __) => h.dragEnds++,
          onNodeDragCancel: (_) => h.dragCancels++,
          nodeBuilder: (context, node) => SizedBox(
            width: node.size,
            height: node.size,
          ),
        ),
      ),
    ),
  );
  controller.reconcileTopology({_bottom, _far}, const {});
  await settleGraphLayout(tester, controller);

  final viewer =
      tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
  viewer.transformationController!.value = Matrix4.identity()
    ..translateByDouble(-20, -20, 0, 1)
    ..scaleByDouble(1.5, 1.5, 1, 1);
  await tester.pump();
  return h;
}
