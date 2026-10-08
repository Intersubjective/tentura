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
  group('camera arbitration by input source during a node drag', () {
    testWidgets('mouse wheel zooms the camera while a node is dragged',
        (tester) async {
      final h = await _pump(tester);
      final owner = await _TrackedMouse.down(tester, h.centre(_bottom));
      await owner.moveBy(const Offset(30, 10));
      await tester.pump();
      expect(h.controller.isCameraGated, isTrue);
      final scaleBefore = h.controller.currentScale;

      await _wheel(tester, owner.at, const Offset(0, -40));
      await tester.pump();

      expect(h.controller.currentScale, greaterThan(scaleBefore));
      expect(h.controller.isCameraGated, isTrue);
      expect(h.dragCancels, 0);

      await owner.up();
      await tester.pump();
      h.controller.dispose();
    });

    testWidgets('wheel zoom during a drag keeps the dragged node under the '
        'pointer', (tester) async {
      final h = await _pump(tester);
      final owner = await _TrackedMouse.down(tester, h.centre(_bottom));
      await owner.moveBy(const Offset(30, 10));
      await tester.pump();
      final scaleBefore = h.controller.currentScale;

      await _wheel(tester, owner.at, const Offset(0, -40));
      await tester.pump();
      expect(h.controller.currentScale, greaterThan(scaleBefore));
      expect(
        h.sceneToGlobal(h.dragPositions.last),
        offsetMoreOrLessEquals(owner.at, epsilon: 0.5),
      );

      await owner.moveBy(const Offset(20, 0));
      await tester.pump();
      expect(
        h.sceneToGlobal(h.dragPositions.last),
        offsetMoreOrLessEquals(owner.at, epsilon: 0.5),
      );

      await owner.up();
      await tester.pump();
      expect(h.dragEnds, 1);
      expect(h.dragCancels, 0);
      expect(h.controller.isCameraGated, isFalse);
      h.controller.dispose();
    });

    testWidgets('wheel zoom focused away from the dragged node keeps the node '
        'under the pointer', (tester) async {
      final h = await _pump(tester);
      final owner = await _TrackedMouse.down(tester, h.centre(_bottom));
      await owner.moveBy(const Offset(30, 10));
      await tester.pump();
      final scaleBefore = h.controller.currentScale;
      final focal = owner.at + const Offset(250, 150);

      // The wheel focal point is far from the drag pointer; a plain zoom
      // about it would slide the node away, so the camera must re-project.
      await _wheel(tester, focal, const Offset(0, -40));
      await tester.pump();

      expect(h.controller.currentScale, greaterThan(scaleBefore));
      expect(
        h.sceneToGlobal(h.dragPositions.last),
        offsetMoreOrLessEquals(owner.at, epsilon: 0.5),
      );

      await owner.moveBy(const Offset(10, 10));
      await tester.pump();
      expect(
        h.sceneToGlobal(h.dragPositions.last),
        offsetMoreOrLessEquals(owner.at, epsilon: 0.5),
      );
      await owner.up();
      await tester.pump();
      expect(h.dragEnds, 1);
      expect(h.dragCancels, 0);
      h.controller.dispose();
    });

    testWidgets('programmatic camera move during a drag keeps the drag alive '
        'and the node under the pointer', (tester) async {
      final h = await _pump(tester);
      final owner = await _TrackedMouse.down(tester, h.centre(_bottom));
      await owner.moveBy(const Offset(30, 10));
      await tester.pump();
      expect(h.controller.isCameraGated, isTrue);
      final cameraBefore = h.camera();

      h.controller.jumpToPosition(const Offset(700, 700));
      await tester.pump();

      expect(h.camera(), isNot(orderedEquals(cameraBefore)));
      expect(h.dragCancels, 0);
      expect(h.controller.isCameraGated, isTrue);
      expect(h.controller.renderSnapshot.presentation.overrides, isNotEmpty);
      expect(
        h.sceneToGlobal(h.dragPositions.last),
        offsetMoreOrLessEquals(owner.at, epsilon: 0.5),
      );

      final updatesBefore = h.dragUpdates;
      await owner.moveBy(const Offset(20, 5));
      await tester.pump();
      expect(h.dragUpdates, greaterThan(updatesBefore));
      expect(
        h.sceneToGlobal(h.dragPositions.last),
        offsetMoreOrLessEquals(owner.at, epsilon: 0.5),
      );

      await owner.up();
      await tester.pump();
      expect(h.dragEnds, 1);
      expect(h.dragCancels, 0);
      expect(h.controller.isCameraGated, isFalse);
      h.controller.dispose();
    });

    testWidgets('trackpad pinch zooms the camera while a node is dragged',
        (tester) async {
      final h = await _pump(tester);
      final owner = await _TrackedMouse.down(tester, h.centre(_bottom));
      await owner.moveBy(const Offset(30, 10));
      await tester.pump();
      final scaleBefore = h.controller.currentScale;

      final pad = TestPointer(9, PointerDeviceKind.trackpad);
      await tester.sendEventToBinding(pad.panZoomStart(owner.at));
      await tester.sendEventToBinding(
        pad.panZoomUpdate(owner.at, scale: 1.4),
      );
      await tester.pump();

      expect(h.controller.currentScale, greaterThan(scaleBefore));
      expect(h.controller.isCameraGated, isTrue);
      expect(
        h.sceneToGlobal(h.dragPositions.last),
        offsetMoreOrLessEquals(owner.at, epsilon: 0.5),
      );

      await tester.sendEventToBinding(pad.panZoomEnd());
      await owner.up();
      await tester.pump();
      expect(h.dragEnds, 1);
      expect(h.dragCancels, 0);
      h.controller.dispose();
    });

    testWidgets('gesture-origin moves during a drag still leave the camera '
        'fixed after a wheel zoom', (tester) async {
      final h = await _pump(tester);
      final owner = await _TrackedMouse.down(tester, h.centre(_bottom));
      await owner.moveBy(const Offset(30, 10));
      await tester.pump();

      await _wheel(tester, owner.at, const Offset(0, -40));
      await tester.pump();
      final zoomed = h.camera();
      expect(zoomed, isNot(orderedEquals(_identityStorage)));

      for (var i = 0; i < 4; i++) {
        await owner.moveBy(const Offset(15, 5));
        expect(h.camera(), orderedEquals(zoomed));
      }
      await tester.pump();
      expect(h.camera(), orderedEquals(zoomed));
      await owner.up();
      await tester.pump();
      h.controller.dispose();
    });

    testWidgets('mouse wheel on the canvas without a drag still zooms',
        (tester) async {
      final h = await _pump(tester);
      final before = h.controller.currentScale;

      await _wheel(
        tester,
        h.sceneToGlobal(const Offset(250, 80)),
        const Offset(0, -40),
      );
      await tester.pump();

      expect(h.controller.currentScale, greaterThan(before));
      h.controller.dispose();
    });
  });

  group('node drag survives viewport resize', () {
    testWidgets('resizing the view mid-drag keeps the drag alive',
        (tester) async {
      final h = await _pump(tester, resizable: true);
      final owner = await _TrackedMouse.down(tester, h.centre(_bottom));
      await owner.moveBy(const Offset(30, 10));
      await tester.pump();
      expect(h.controller.isCameraGated, isTrue);
      final updatesBefore = h.dragUpdates;

      h.resize(const Size(900, 700));
      await tester.pump();
      await tester.pump();

      expect(h.dragCancels, 0);
      expect(h.controller.isCameraGated, isTrue);
      expect(h.controller.renderSnapshot.presentation.overrides, isNotEmpty);
      // The view origin moved with the resize; the camera must re-project so
      // the dragged node is still under the stationary pointer.
      expect(
        h.sceneToGlobal(h.dragPositions.last),
        offsetMoreOrLessEquals(owner.at, epsilon: 0.5),
      );

      await owner.moveBy(const Offset(25, 0));
      await tester.pump();
      expect(h.dragUpdates, greaterThan(updatesBefore));
      expect(
        h.sceneToGlobal(h.dragPositions.last),
        offsetMoreOrLessEquals(owner.at, epsilon: 0.5),
      );

      await owner.up();
      await tester.pump();
      expect(h.dragEnds, 1);
      expect(h.dragCancels, 0);
      expect(h.controller.isCameraGated, isFalse);
      h.controller.dispose();
    });

    testWidgets('layout constraint change mid-drag keeps the drag alive',
        (tester) async {
      final h = await _pump(tester);
      final owner = await _TrackedMouse.down(tester, h.centre(_bottom));
      await owner.moveBy(const Offset(30, 10));
      await tester.pump();
      expect(h.controller.isCameraGated, isTrue);

      h.controller.handleLayoutConstraintsChangedForTesting(
        const Size(900, 700),
      );
      h.controller.handleLayoutConstraintsChangedForTesting(
        const Size(640, 480),
      );
      await tester.pump();

      expect(h.dragCancels, 0);
      expect(h.controller.isCameraGated, isTrue);
      expect(h.controller.renderSnapshot.presentation.overrides, isNotEmpty);
      // Re-projection must happen at the change itself, not on the next move.
      expect(
        h.sceneToGlobal(h.dragPositions.last),
        offsetMoreOrLessEquals(owner.at, epsilon: 0.5),
      );

      final updatesBefore = h.dragUpdates;
      await owner.moveBy(const Offset(25, 0));
      await tester.pump();
      expect(h.dragUpdates, greaterThan(updatesBefore));
      await owner.up();
      await tester.pump();
      expect(h.dragEnds, 1);
      expect(h.dragCancels, 0);
      h.controller.dispose();
    });

    testWidgets('touch drag keeps going after the view is resized',
        (tester) async {
      final h = await _pump(tester, resizable: true);
      final owner = await tester.createGesture();
      var touchAt = h.centre(_bottom);
      await owner.down(touchAt);
      for (var i = 0; i < 5; i++) {
        touchAt += const Offset(12, 4);
        await owner.moveBy(const Offset(12, 4));
      }
      await tester.pump();
      expect(h.dragStarts, [_bottom]);

      h.resize(const Size(700, 500));
      await tester.pump();
      await tester.pump();
      expect(h.dragCancels, 0);
      expect(
        h.sceneToGlobal(h.dragPositions.last),
        offsetMoreOrLessEquals(touchAt, epsilon: 0.5),
      );

      final updatesBefore = h.dragUpdates;
      touchAt += const Offset(20, 10);
      await owner.moveBy(const Offset(20, 10));
      await tester.pump();
      expect(h.dragUpdates, greaterThan(updatesBefore));
      expect(
        h.sceneToGlobal(h.dragPositions.last),
        offsetMoreOrLessEquals(touchAt, epsilon: 0.5),
      );
      await owner.up();
      await tester.pump();
      expect(h.dragEnds, 1);
      expect(h.dragCancels, 0);
      h.controller.dispose();
    });
  });
}

Future<void> _wheel(WidgetTester tester, Offset at, Offset delta) async {
  final pointer = TestPointer(5, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(pointer.hover(at));
  await tester.sendEventToBinding(pointer.scroll(delta));
}

class _TrackedMouse {
  _TrackedMouse(this._gesture, this.at);

  static Future<_TrackedMouse> down(WidgetTester tester, Offset at) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(at);
    return _TrackedMouse(gesture, at);
  }

  final TestGesture _gesture;
  Offset at;

  Future<void> moveBy(Offset delta) async {
    at += delta;
    await _gesture.moveBy(delta);
  }

  Future<void> up() => _gesture.up();
}

final _identityStorage = Matrix4.identity().storage.toList();

class _Harness {
  _Harness(this.tester, this.controller);

  final WidgetTester tester;
  final GraphController<Node<int>, Edge<Node<int>, int>> controller;
  final List<Node<int>> dragStarts = [];
  final List<Offset> dragPositions = [];
  int dragUpdates = 0;
  int dragEnds = 0;
  int dragCancels = 0;
  late void Function(Size) resize;

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

Future<_Harness> _pump(WidgetTester tester, {bool resizable = false}) async {
  final controller = testIntIntGraphController();
  final h = _Harness(tester, controller);
  tester.view.physicalSize = const Size(1000, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  var surface = const Size(800, 600);
  await tester.pumpWidget(
    MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) {
          h.resize = (size) => setState(() => surface = size);
          return Align(
            alignment:
                resizable ? Alignment.bottomRight : Alignment.topLeft,
            child: SizedBox(
              width: surface.width,
              height: surface.height,
              child: GraphView<Node<int>, Edge<Node<int>, int>>(
                controller: controller,
                canvasSize: const GraphCanvasSize.fixed(Size(1000, 1000)),
                layoutAlgorithm: FixedSceneLayoutAlgorithm({
                  '3': ScenePoint(x: 150, y: 250),
                  '4': ScenePoint(x: 400, y: 400),
                }),
                onNodeDragStart: (node, position) => h.dragStarts.add(node),
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
          );
        },
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
