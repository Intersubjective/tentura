import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'support/fixed_scene_layout.dart';
import 'support/int_graph_controller.dart';

void main() {
  testWidgets('graph interpolates towards a newly computed layout',
      (tester) async {
    final controller = testIntGraphController();
    const a = Node<int>(data: 1, size: 10);
    const b = Node<int>(data: 2, size: 10);

    await tester.pumpWidget(
      MaterialApp(
        home: GraphView<Node<int>, Edge<Node<int>, void>>(
          controller: controller,
          canvasSize: const GraphCanvasSize.fixed(Size(500, 500)),
          layoutAlgorithm: FixedSceneLayoutAlgorithm({
            '1': ScenePoint(x: 100, y: 100),
            '2': ScenePoint(x: 300, y: 300),
          }),
          layoutTransitionDuration: const Duration(milliseconds: 300),
          nodeBuilder: (context, node) => const SizedBox.shrink(),
        ),
      ),
    );

    testAddNode(controller, a);
    await tester.pumpAndSettle();
    final first = testNodePosition(controller, a);

    testAddNode(controller, b);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(controller.isLayoutSettling, isTrue);
    expect(controller.isLayoutTransitioning, isTrue);

    expect(controller.canLayout, isTrue);
    expect(
      controller.getPositionOrNullForId(testIntNodeId(a)),
      isNotNull,
    );

    await tester.pumpAndSettle();
    expect(controller.isLayoutSettling, isFalse);
    expect(controller.isLayoutTransitioning, isFalse);
    expect(
      controller.getPositionOrNullForId(testIntNodeId(b)),
      isNotNull,
    );
    expect(first, isNotNull);

    controller.dispose();
  });

  testWidgets('a new node starts at its initial position and tweens out',
      (tester) async {
    final controller = testIntGraphController();
    addTearDown(controller.dispose);
    const a = Node<int>(data: 1, size: 10);
    const b = Node<int>(data: 2, size: 10);

    await tester.pumpWidget(
      MaterialApp(
        home: GraphView<Node<int>, Edge<Node<int>, void>>(
          controller: controller,
          canvasSize: const GraphCanvasSize.fixed(Size(500, 500)),
          layoutAlgorithm: FixedSceneLayoutAlgorithm({
            '1': ScenePoint(x: 100, y: 100),
            '2': ScenePoint(x: 300, y: 300),
          }),
          layoutTransitionDuration: const Duration(milliseconds: 300),
          nodeBuilder: (context, node) => const SizedBox.shrink(),
        ),
      ),
    );
    testAddNode(controller, a);
    await tester.pumpAndSettle();

    controller.reconcileTopology(
      {a, b},
      const {},
      requestLayout: true,
      initialPositions: {
        '2': const Offset(100, 100),
        // Ignored: already in the scene, and not in the target set.
        '1': Offset.zero,
        '9': const Offset(7, 7),
      },
    );
    expect(testNodePosition(controller, b), const Offset(100, 100));
    expect(testNodePosition(controller, a), const Offset(100, 100));

    expect(controller.spawningNodeIds, {'2'});
    List<String> painted() => controller.orderedRenderNodeIds(
          controller.renderSnapshot,
          configuredPaintOrder: const ['1', '2'],
        );
    expect(painted(), ['2', '1'], reason: 'spawns from under node 1');

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final mid = testNodePosition(controller, b);
    expect(mid.dx, inExclusiveRange(100, 300));
    expect(mid.dy, inExclusiveRange(100, 300));
    expect(painted(), ['2', '1']);

    await tester.pumpAndSettle();
    expect(testNodePosition(controller, b), const Offset(300, 300));
    expect(controller.spawningNodeIds, isEmpty);
    expect(painted(), ['1', '2']);
  });

  testWidgets('without an initial position a new node starts at the centre',
      (tester) async {
    final controller = testIntGraphController();
    addTearDown(controller.dispose);
    const a = Node<int>(data: 1, size: 10);
    const b = Node<int>(data: 2, size: 10);

    await tester.pumpWidget(
      MaterialApp(
        home: GraphView<Node<int>, Edge<Node<int>, void>>(
          controller: controller,
          canvasSize: const GraphCanvasSize.fixed(Size(500, 500)),
          layoutAlgorithm: FixedSceneLayoutAlgorithm({
            '1': ScenePoint(x: 100, y: 100),
            '2': ScenePoint(x: 300, y: 300),
          }),
          layoutTransitionDuration: const Duration(milliseconds: 300),
          nodeBuilder: (context, node) => const SizedBox.shrink(),
        ),
      ),
    );
    testAddNode(controller, a);
    await tester.pumpAndSettle();

    testAddNode(controller, b);
    expect(testNodePosition(controller, b), const Offset(250, 250));
    await tester.pumpAndSettle();
    expect(testNodePosition(controller, b), const Offset(300, 300));
  });

  testWidgets('a node removed mid-spawn and restored starts at its seed again',
      (tester) async {
    final controller = testIntGraphController();
    addTearDown(controller.dispose);
    const a = Node<int>(data: 1, size: 10);
    const b = Node<int>(data: 2, size: 10);
    const c = Node<int>(data: 3, size: 10);

    await tester.pumpWidget(
      MaterialApp(
        home: GraphView<Node<int>, Edge<Node<int>, void>>(
          controller: controller,
          canvasSize: const GraphCanvasSize.fixed(Size(500, 500)),
          layoutAlgorithm: FixedSceneLayoutAlgorithm({
            '1': ScenePoint(x: 100, y: 100),
            '2': ScenePoint(x: 300, y: 300),
            '3': ScenePoint(x: 400, y: 100),
          }),
          layoutTransitionDuration: const Duration(milliseconds: 300),
          nodeBuilder: (context, node) => const SizedBox.shrink(),
        ),
      ),
    );
    testAddNode(controller, a);
    await tester.pumpAndSettle();

    const seed = {'2': Offset(100, 100)};
    controller.reconcileTopology(
      {a, b},
      const {},
      requestLayout: true,
      initialPositions: seed,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(testNodePosition(controller, b), isNot(const Offset(100, 100)));

    // Off and on again before any new layout lands.
    controller.reconcileTopology({a}, const {});
    expect(controller.spawningNodeIds, isEmpty);
    controller.reconcileTopology({a, b}, const {}, initialPositions: seed);
    expect(testNodePosition(controller, b), const Offset(100, 100));
    expect(controller.spawningNodeIds, {'2'});

    await tester.pumpAndSettle();
    expect(testNodePosition(controller, b), const Offset(300, 300));
    expect(controller.spawningNodeIds, isEmpty);

    // A spawn whose tween a topology change cuts short, with no new layout
    // to finish it, no longer paints beneath the rest.
    controller.reconcileTopology({a}, const {}, requestLayout: true);
    await tester.pumpAndSettle();
    controller.reconcileTopology(
      {a, b},
      const {},
      requestLayout: true,
      initialPositions: seed,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.spawningNodeIds, {'2'});
    controller.reconcileTopology(
      {a, b, c},
      const {},
      layoutOnTopologyChange: false,
    );
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.spawningNodeIds, isEmpty);
    await tester.pumpAndSettle();
  });
}
