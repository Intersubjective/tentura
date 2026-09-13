import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:force_directed_graphview/src/widget/graph_layout_view.dart';
import 'package:force_directed_graphview/src/widget/node_drag_gesture.dart';

import 'support/fixed_scene_layout.dart';
import 'support/int_graph_controller.dart';
import 'support/settle_graph_layout.dart';

void _logMemory(String label) {
  try {
    final mem = File('/proc/meminfo').readAsLinesSync();
    String? avail;
    String? swapFree;
    for (final line in mem) {
      if (line.startsWith('MemAvailable:')) {
        avail = line.trim();
      } else if (line.startsWith('SwapFree:')) {
        swapFree = line.trim();
      }
    }
    // ignore: avoid_print
    print('MEM $label: ${avail ?? "?"} | ${swapFree ?? "?"}');
  } on Object {
    // ignore: avoid_print
    print('MEM $label: (unavailable)');
  }
}

void main() {
  const viewport = Size(800, 600);
  const canvas = Size(500, 500);

  Future<void> pumpHarness(
    WidgetTester tester,
    GraphController<Node<int>, Edge<Node<int>, int>> controller, {
    SceneLayoutAlgorithm? algorithm,
    Duration transitionDuration = Duration.zero,
    NodeDragStartCallback<Node<int>>? onNodeDragStart,
    NodeDragUpdateCallback<Node<int>>? onNodeDragUpdate,
    NodeDragEndCallback<Node<int>>? onNodeDragEnd,
    NodeDragCancelCallback<Node<int>>? onNodeDragCancel,
  }) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: viewport.width,
          height: viewport.height,
          child: GraphView<Node<int>, Edge<Node<int>, int>>(
            controller: controller,
            canvasSize: const GraphCanvasSize.fixed(canvas),
            layoutAlgorithm: algorithm ??
                FixedSceneLayoutAlgorithm({
                  '1': ScenePoint(x: 120, y: 200),
                  '2': ScenePoint(x: 280, y: 200),
                }),
            layoutTransitionDuration: transitionDuration,
            onNodeDragStart: onNodeDragStart ?? (_, __) {},
            onNodeDragUpdate: onNodeDragUpdate,
            onNodeDragEnd: onNodeDragEnd,
            onNodeDragCancel: onNodeDragCancel,
            nodeBuilder: (context, node) => SizedBox(
              width: node.size,
              height: node.size,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('nonzero transition capture freezes displayed position', (tester) async {
    _logMemory('before nonzero transition capture');
    final controller = testIntIntGraphController();
    const a = Node<int>(data: 1, size: 80);
    const b = Node<int>(data: 2, size: 80);

    await pumpHarness(
      tester,
      controller,
      algorithm: const FruchtermanReingoldSceneLayoutAlgorithm(iterations: 1),
      transitionDuration: const Duration(milliseconds: 400),
    );

    testAddNode(controller, a);
    await settleGraphLayout(tester, controller);
    final settledA = testNodePosition(controller, a);

    testAddNode(controller, b);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(controller.isLayoutTransitioning, isTrue);

    final midA = testNodePosition(controller, a);
    expect(midA, isNot(equals(settledA)));

    final box = tester.renderObject<RenderBox>(find.byType(GraphLayoutView));
    final down = box.localToGlobal(midA);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(down);
    await gesture.moveBy(const Offset(12, 0));
    await tester.pump();

    final capturedA = testNodePosition(controller, a);
    expect(capturedA.dx, greaterThan(midA.dx - 1));
    final layoutTarget = controller.renderSnapshot.layout!.positions['1']!;
    expect(
      capturedA,
      isNot(Offset(layoutTarget.x, layoutTarget.y)),
    );
    expect(
      controller.renderSnapshot.transition?.positions['1'],
      isNotNull,
    );

    await gesture.up();
    controller.dispose();
    _logMemory('after nonzero transition capture');
  });

  testWidgets('terminal releaseOnTerminal does not snap back via stale transition',
      (tester) async {
    _logMemory('before terminal release');
    final controller = testIntIntGraphController();
    const node = Node<int>(data: 1, size: 80);

    await pumpHarness(
      tester,
      controller,
      algorithm: FixedSceneLayoutAlgorithm({
        '1': ScenePoint(x: 10, y: 10),
      }),
      transitionDuration: const Duration(milliseconds: 300),
    );

    testAddNode(controller, node);
    await settleGraphLayout(tester, controller);

    final token = controller.beginNodePresentationDragForId(testIntNodeId(
      node),
      const Offset(50, 50),
    );
    controller.requestSceneLayout(releaseOnTerminal: {token});
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (!controller.isLayoutSettling &&
          controller.renderSnapshot.presentation.overrides.isEmpty) {
        break;
      }
    }

    expect(testNodePosition(controller, node), const Offset(10, 10));
    expect(controller.renderSnapshot.presentation.overrides, isEmpty);
    expect(controller.renderSnapshot.transition, isNull);

    controller.dispose();
    _logMemory('after terminal release');
  });

  testWidgets('controller swap during drag aborts capture once', (tester) async {
    _logMemory('before swap during drag');
    final first = testIntIntGraphController();
    final second = testIntIntGraphController();
    var cancelCount = 0;

    await pumpHarness(
      tester,
      first,
      onNodeDragCancel: (_) => cancelCount++,
    );

    testAddNode(first, const Node<int>(data: 1, size: 80));
    await settleGraphLayout(tester, first);

    final centre = testNodePosition(first, const Node<int>(data: 1, size: 80));
    final box = tester.renderObject<RenderBox>(find.byType(GraphLayoutView));
    final global = box.localToGlobal(centre);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(global);
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    expect(first.isCameraGated, isTrue);

    await pumpHarness(
      tester,
      second,
      onNodeDragCancel: (_) => cancelCount++,
    );
    testAddNode(second, const Node<int>(data: 1, size: 80));
    await settleGraphLayout(tester, second);

    expect(cancelCount, 1);
    expect(first.isCameraGated, isFalse);

    await gesture.up();
    first.dispose();
    second.dispose();
    _logMemory('after swap during drag');
  });

  testWidgets('pending long-press clears when controller swaps', (tester) async {
    _logMemory('before pending longpress swap');
    final first = testIntIntGraphController();
    final second = testIntIntGraphController();
    Node<int>? started;

    await pumpHarness(
      tester,
      first,
      onNodeDragStart: (node, _) => started = node,
    );

    testAddNode(first, const Node<int>(data: 1, size: 80));
    await settleGraphLayout(tester, first);

    final centre = testNodePosition(first, const Node<int>(data: 1, size: 80));
    final box = tester.renderObject<RenderBox>(find.byType(GraphLayoutView));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.touch);
    await gesture.down(box.localToGlobal(centre));
    await tester.pump(const Duration(milliseconds: 200));

    await pumpHarness(
      tester,
      second,
      onNodeDragStart: (node, _) => started = node,
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(started, isNull);
    expect(first.isCameraGated, isFalse);

    await gesture.up();
    first.dispose();
    second.dispose();
    _logMemory('after pending longpress swap');
  });

  testWidgets('rejects two live GraphViews on one controller', (tester) async {
    _logMemory('before two live views');
    final controller = testIntIntGraphController();
    testAddNode(controller, const Node<int>(data: 1, size: 40));

    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            SizedBox(
              width: 400,
              height: 400,
              child: GraphView<Node<int>, Edge<Node<int>, int>>(
                controller: controller,
                canvasSize: const GraphCanvasSize.fixed(canvas),
                layoutAlgorithm: FixedSceneLayoutAlgorithm({
                  '1': ScenePoint(x: 100, y: 100),
                }),
                onNodeDragStart: (_, __) {},
                nodeBuilder: (_, node) => SizedBox(
                  width: node.size,
                  height: node.size,
                ),
              ),
            ),
            SizedBox(
              width: 400,
              height: 400,
              child: GraphView<Node<int>, Edge<Node<int>, int>>(
                controller: controller,
                canvasSize: const GraphCanvasSize.fixed(canvas),
                layoutAlgorithm: FixedSceneLayoutAlgorithm({
                  '1': ScenePoint(x: 100, y: 100),
                }),
                onNodeDragStart: (_, __) {},
                nodeBuilder: (_, node) => SizedBox(
                  width: node.size,
                  height: node.size,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    final attachError = tester.takeException();
    expect(attachError, isA<StateError>());
    expect(
      (attachError as StateError).message,
      contains('already attached to another GraphView'),
    );

    controller.dispose();
    _logMemory('after two live views');
  });

  testWidgets('unmount detaches gestures without disposing controller',
      (tester) async {
    _logMemory('before unmount');
    final controller = testIntIntGraphController();
    var cancelled = false;

    await pumpHarness(
      tester,
      controller,
      onNodeDragCancel: (_) => cancelled = true,
    );
    testAddNode(controller, const Node<int>(data: 1, size: 80));
    await settleGraphLayout(tester, controller);

    final centre = testNodePosition(controller, const Node<int>(data: 1, size: 80));
    final box = tester.renderObject<RenderBox>(find.byType(GraphLayoutView));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(box.localToGlobal(centre));
    await gesture.moveBy(const Offset(18, 0));
    await tester.pump();
    expect(controller.isCameraGated, isTrue);
    expect(controller.renderSnapshot.presentation.overrides, isNotEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(cancelled, isTrue);
    expect(controller.renderSnapshot.presentation.overrides, isEmpty);
    expect(controller.isCameraGated, isFalse);

    await gesture.up();
    controller.dispose();
    _logMemory('after unmount');
  });

  testWidgets('viewport resize aborts active capture', (tester) async {
    _logMemory('before resize');
    final controller = testIntIntGraphController();
    var cancelled = false;
    var surface = viewport;
    late void Function(void Function()) resizeSurface;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            resizeSurface = setState;
            return SizedBox(
              width: surface.width,
              height: surface.height,
              child: GraphView<Node<int>, Edge<Node<int>, int>>(
                controller: controller,
                canvasSize: const GraphCanvasSize.fixed(canvas),
                layoutAlgorithm: FixedSceneLayoutAlgorithm({
                  '1': ScenePoint(x: 120, y: 200),
                }),
                onNodeDragStart: (_, __) {},
                onNodeDragCancel: (_) => cancelled = true,
                nodeBuilder: (context, node) => SizedBox(
                  width: node.size,
                  height: node.size,
                ),
              ),
            );
          },
        ),
      ),
    );
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    testAddNode(controller, const Node<int>(data: 1, size: 80));
    await settleGraphLayout(tester, controller);

    final centre = testNodePosition(controller, const Node<int>(data: 1, size: 80));
    final box = tester.renderObject<RenderBox>(find.byType(GraphLayoutView));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(box.localToGlobal(centre));
    await gesture.moveBy(const Offset(18, 0));
    await tester.pump();
    expect(controller.isCameraGated, isTrue);

    resizeSurface(() {
      surface = const Size(900, 700);
    });
    await tester.pump();
    controller.handleLayoutConstraintsChangedForTesting(const Size(900, 700));
    await tester.pump();

    expect(cancelled, isTrue);
    expect(controller.renderSnapshot.presentation.overrides, isEmpty);
    expect(controller.isCameraGated, isFalse);

    await gesture.up();
    controller.dispose();
    _logMemory('after resize');
  });

  testWidgets('throwing drag start callback releases camera gate', (tester) async {
    _logMemory('before throwing start');
    final controller = testIntIntGraphController();

    await pumpHarness(
      tester,
      controller,
      onNodeDragStart: (_, __) => throw StateError('boom'),
    );
    testAddNode(controller, const Node<int>(data: 1, size: 80));
    await settleGraphLayout(tester, controller);

    final centre = testNodePosition(controller, const Node<int>(data: 1, size: 80));
    final box = tester.renderObject<RenderBox>(find.byType(GraphLayoutView));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(box.localToGlobal(centre));

    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();

    expect(tester.takeException(), isA<StateError>());
    expect(controller.isCameraGated, isFalse);
    expect(find.byType(NodeDragGesture), findsOneWidget);

    await gesture.up();
    controller.dispose();
    _logMemory('after throwing start');
  });

  testWidgets('programmatic camera move during capture cancels drag', (tester) async {
    _logMemory('before programmatic camera');
    final controller = testIntIntGraphController();
    var cancelled = false;

    await pumpHarness(
      tester,
      controller,
      onNodeDragCancel: (_) => cancelled = true,
    );
    testAddNode(controller, const Node<int>(data: 1, size: 80));
    await settleGraphLayout(tester, controller);

    final centre = testNodePosition(controller, const Node<int>(data: 1, size: 80));
    final box = tester.renderObject<RenderBox>(find.byType(GraphLayoutView));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(box.localToGlobal(centre));
    await gesture.moveBy(const Offset(18, 0));
    await tester.pump();
    expect(controller.isCameraGated, isTrue);

    controller.jumpToCenter();
    await tester.pump();

    expect(cancelled, isTrue);
    expect(controller.isCameraGated, isFalse);

    await gesture.up();
    controller.dispose();
    _logMemory('after programmatic camera');
  });
}
