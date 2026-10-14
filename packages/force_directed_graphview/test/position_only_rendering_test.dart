import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:force_directed_graphview/src/widget/graph_layout_view.dart';

import 'support/fixed_scene_layout.dart';
import 'support/int_graph_controller.dart';
import 'support/settle_graph_layout.dart';

void main() {
  group('Position-only scene rendering', () {
    testWidgets(
      'paint and hit targets move together without rebuilding unchanged nodes',
      (tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final controller = testIntIntGraphController();
        addTearDown(controller.dispose);
        final edgePainter = _RecordingEdgePainter();
        final builds = <int, int>{};
        final tapped = <int>[];
        final canvasTaps = <Offset>[];
        const moving = Node<int>(data: 1, size: 40);
        const stationary = Node<int>(data: 2, size: 40);
        const edge = Edge<Node<int>, int>(
          source: moving,
          destination: stationary,
          data: 1,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: GraphView<Node<int>, Edge<Node<int>, int>>(
              controller: controller,
              canvasSize: const GraphCanvasSize.fixed(Size(500, 500)),
              layoutAlgorithm: FixedSceneLayoutAlgorithm({
                '1': ScenePoint(x: 150, y: 150),
                '2': ScenePoint(x: 150, y: 330),
              }),
              edgePainter: edgePainter,
              onNodeTap: (node) => tapped.add(node.data),
              onCanvasTap: canvasTaps.add,
              nodeBuilder: (context, node) {
                builds.update(
                  node.data,
                  (count) => count + 1,
                  ifAbsent: () => 1,
                );
                return SizedBox(
                  key: ValueKey('node-${node.data}'),
                  width: node.size,
                  height: node.size,
                );
              },
            ),
          ),
        );
        controller.reconcileTopology({moving, stationary}, {edge});
        await settleGraphLayout(tester, controller);
        await tester.pumpAndSettle();

        final buildsBeforeMove = Map<int, int>.of(builds);
        final topologyRevision = controller.scene.topologyRevision;
        final sceneRevision = controller.sceneRevision;
        final layoutCount = controller.relayoutInvocationCount;
        final oldCentre =
            tester.getCenter(find.byKey(const ValueKey('node-1')));
        final stationaryCentre =
            tester.getCenter(find.byKey(const ValueKey('node-2')));
        final paintCount = edgePainter.calls.length;

        final token = controller.beginNodePresentationDragForId(
          '1',
          const Offset(150, 150),
        );
        controller.updateNodePresentationDrag(token, const Offset(330, 150));
        await tester.pump();

        final graphBox =
            tester.renderObject<RenderBox>(find.byType(GraphLayoutView));
        final newCentre = graphBox.localToGlobal(const Offset(330, 150));
        expect(
          tester.getCenter(find.byKey(const ValueKey('node-1'))),
          newCentre,
        );
        expect(
          tester.getCenter(find.byKey(const ValueKey('node-2'))),
          stationaryCentre,
        );
        expect(edgePainter.calls.length, greaterThan(paintCount));
        expect(
          edgePainter.calls.last,
          (const Offset(330, 150), const Offset(150, 330)),
        );
        expect(controller.sceneRevision, greaterThan(sceneRevision));
        expect(controller.scene.topologyRevision, topologyRevision);
        expect(controller.relayoutInvocationCount, layoutCount);

        await tester.tapAt(newCentre);
        await tester.pump();
        expect(tapped, [1]);
        await tester.tapAt(oldCentre);
        await tester.pump();
        expect(
          tapped,
          [1],
          reason: 'The old painted position is no longer a hit',
        );
        expect(canvasTaps, hasLength(1));
        await tester.tapAt(stationaryCentre);
        await tester.pump();
        expect(tapped, [1, 2]);
        expect(
          builds[2],
          buildsBeforeMove[2],
          reason: 'A position-only change must not rebuild unchanged nodes',
        );

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  });
}

final class _RecordingEdgePainter
    implements EdgePainter<Node<int>, Edge<Node<int>, int>> {
  final calls = <(Offset, Offset)>[];

  @override
  void paint(
    Canvas canvas,
    Edge<Node<int>, int> edge,
    Offset sourcePosition,
    Offset destinationPosition,
  ) {
    calls.add((sourcePosition, destinationPosition));
  }
}
