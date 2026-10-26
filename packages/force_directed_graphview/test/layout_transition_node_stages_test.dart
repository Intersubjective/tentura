import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'support/fixed_scene_layout.dart';
import 'support/int_graph_controller.dart';

const _start = Offset(100, 100);

// Two groups of nodes, each travelling from the same start to its own target.
final _firstGroup = {
  1: ScenePoint(x: 300, y: 100),
  2: ScenePoint(x: 300, y: 200)
};
final _secondGroup = {
  3: ScenePoint(x: 100, y: 300),
  4: ScenePoint(x: 200, y: 300),
};

const _stages = <GraphNodeId, LayoutTransitionStage>{
  '1': LayoutTransitionStage(
    delay: Duration.zero,
    duration: Duration(milliseconds: 200),
  ),
  '2': LayoutTransitionStage(
    delay: Duration.zero,
    duration: Duration(milliseconds: 200),
  ),
  '3': LayoutTransitionStage(
    delay: Duration(milliseconds: 200),
    duration: Duration(milliseconds: 200),
  ),
  '4': LayoutTransitionStage(
    delay: Duration(milliseconds: 200),
    duration: Duration(milliseconds: 200),
  ),
};

Future<GraphController<Node<int>, Edge<Node<int>, void>>> _mount(
  WidgetTester tester,
) async {
  final controller = testIntGraphController();
  addTearDown(controller.dispose);
  final nodes = [
    for (final id in [1, 2, 3, 4]) Node<int>(data: id, size: 10),
  ];

  await tester.pumpWidget(
    MaterialApp(
      home: GraphView<Node<int>, Edge<Node<int>, void>>(
        controller: controller,
        canvasSize: const GraphCanvasSize.fixed(Size(500, 500)),
        layoutAlgorithm: FixedSceneLayoutAlgorithm({
          for (final e in [..._firstGroup.entries, ..._secondGroup.entries])
            '${e.key}': e.value,
        }),
        layoutTransitionDuration: const Duration(milliseconds: 400),
        layoutTransitionStages: _stages,
        nodeBuilder: (context, node) => const SizedBox.shrink(),
      ),
    ),
  );
  controller.reconcileTopology(
    nodes.toSet(),
    const {},
    requestLayout: true,
    initialPositions: {for (final n in nodes) '${n.data}': _start},
  );
  await tester.pump();
  return controller;
}

double _progress(
  GraphController<Node<int>, Edge<Node<int>, void>> controller,
  int id,
  ScenePoint target,
) {
  final point = controller.renderSnapshot.resolvePosition('$id')!;
  final path = Offset(target.x, target.y) - _start;
  final moved = Offset(point.x, point.y) - _start;
  return (moved.dx * path.dx + moved.dy * path.dy) /
      (path.dx * path.dx + path.dy * path.dy);
}

void main() {
  group('layout transition node stages', () {
    testWidgets('nodes of a stage start only when their stage begins', (
      tester,
    ) async {
      final controller = await _mount(tester);

      await tester.pump(const Duration(milliseconds: 100));
      for (final e in _firstGroup.entries) {
        expect(_progress(controller, e.key, e.value), greaterThan(0.1));
      }
      for (final e in _secondGroup.entries) {
        expect(_progress(controller, e.key, e.value), 0);
      }

      await tester.pump(const Duration(milliseconds: 200));
      for (final e in _firstGroup.entries) {
        expect(_progress(controller, e.key, e.value), closeTo(1, 1e-6));
      }
      for (final e in _secondGroup.entries) {
        expect(_progress(controller, e.key, e.value), inExclusiveRange(0, 1));
      }
    });

    testWidgets('nodes of one stage are equally far along at every frame', (
      tester,
    ) async {
      final controller = await _mount(tester);

      for (var frame = 0; frame < 30; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        final first = [
          for (final e in _firstGroup.entries)
            _progress(controller, e.key, e.value),
        ];
        final second = [
          for (final e in _secondGroup.entries)
            _progress(controller, e.key, e.value),
        ];
        expect(first[0], closeTo(first[1], 1e-6));
        expect(second[0], closeTo(second[1], 1e-6));
      }
    });

    testWidgets('every node ends at its target after the last stage', (
      tester,
    ) async {
      final controller = await _mount(tester);

      await tester.pumpAndSettle();

      for (final e in [..._firstGroup.entries, ..._secondGroup.entries]) {
        final point = controller.renderSnapshot.resolvePosition('${e.key}')!;
        expect(point, e.value);
      }
      expect(controller.isLayoutTransitioning, isFalse);
    });

    testWidgets('nodes without a stage use the whole-transition timing', (
      tester,
    ) async {
      final controller = testIntGraphController();
      addTearDown(controller.dispose);
      final nodes = [
        for (final id in [1, 2]) Node<int>(data: id, size: 10),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: GraphView<Node<int>, Edge<Node<int>, void>>(
            controller: controller,
            canvasSize: const GraphCanvasSize.fixed(Size(500, 500)),
            layoutAlgorithm: FixedSceneLayoutAlgorithm({
              '1': _firstGroup[1]!,
              '2': _firstGroup[2]!,
            }),
            layoutTransitionDuration: const Duration(milliseconds: 400),
            layoutTransitionStages: const {
              '1': LayoutTransitionStage(
                delay: Duration(milliseconds: 200),
                duration: Duration(milliseconds: 200),
              ),
            },
            nodeBuilder: (context, node) => const SizedBox.shrink(),
          ),
        ),
      );
      controller.reconcileTopology(
        nodes.toSet(),
        const {},
        requestLayout: true,
        initialPositions: {for (final n in nodes) '${n.data}': _start},
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(_progress(controller, 1, _firstGroup[1]!), 0);
      expect(_progress(controller, 2, _firstGroup[2]!), greaterThan(0.1));
    });
  });
}
