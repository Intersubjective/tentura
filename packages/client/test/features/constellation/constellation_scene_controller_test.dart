import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/ui/scene/constellation_scene_controller.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';

const _nodeA = FieldPersonNode(
  person: Profile(id: 'a', displayName: 'A'),
  ring: 1,
  isKept: false,
);
const _nodeB = FieldPersonNode(
  person: Profile(id: 'b', displayName: 'B'),
  ring: 1,
  isKept: false,
);

final class _InstantAlgorithm implements SceneLayoutAlgorithm {
  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) async* {
    yield GraphLayoutFrame(
      ticket: request.ticket,
      sequence: 0,
      positions: {
        for (final id in request.nodeIds) id: ScenePoint(x: 1, y: 1),
      },
      isTerminal: true,
    );
  }
}

/// Holds the terminal frame back until [release] so presentation tokens can be
/// observed while the layout is still running.
final class _GatedAlgorithm implements SceneLayoutAlgorithm {
  final _gate = Completer<void>();
  var requests = 0;

  void release() => _gate.complete();

  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) async* {
    requests++;
    await _gate.future;
    yield GraphLayoutFrame(
      ticket: request.ticket,
      sequence: 0,
      positions: {
        for (final id in request.nodeIds) id: ScenePoint(x: 9, y: 9),
      },
      isTerminal: true,
    );
  }
}

Future<void> _settle(
  WidgetTester tester,
  GraphController<NodeDetails, EdgeDetails> controller,
) async {
  for (var i = 0; i < 50; i++) {
    if (controller.scene.layoutOutcome is! GraphLayoutOutcomeRunning) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 5));
  }
}

/// Post-frame callbacks only fire on a frame; make sure one is scheduled.
Future<void> _frame(WidgetTester tester) async {
  tester.binding.scheduleFrame();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

class _Harness {
  _Harness(this.scene);

  final ConstellationSceneController scene;

  GraphController<NodeDetails, EdgeDetails> get graph => scene.graphController;

  String get idA => _nodeA.graphNodeId;
  String get idB => _nodeB.graphNodeId;

  GraphPresentationToken? tokenOf(String id) =>
      graph.activePresentationTokenForNode(id);
}

Future<_Harness> _mount(WidgetTester tester) async {
  final scene = ConstellationSceneController();
  addTearDown(scene.graphController.dispose);
  scene.graphController.reconcileTopology(
    {_nodeA, _nodeB},
    <EdgeDetails>{},
    layoutOnTopologyChange: false,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: SizedBox(
        width: 800,
        height: 600,
        child: GraphView<NodeDetails, EdgeDetails>(
          controller: scene.graphController,
          canvasSize: const GraphCanvasSize.fixed(Size(2000, 2000)),
          layoutAlgorithm: _InstantAlgorithm(),
          nodeBuilder: (_, node) => SizedBox.square(
            dimension: 20,
            child: Text(node.label),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await _settle(tester, scene.graphController);
  final harness = _Harness(scene);
  expect(harness.graph.canLayout, isTrue);
  return harness;
}

void main() {
  group('ConstellationSceneController layout hand-off', () {
    testWidgets('placement hand-off releases only the handed-off node on '
        'the terminal outcome', (tester) async {
      final h = await _mount(tester);
      final tokenA = h.graph.beginNodePresentationDragForId(
        h.idA,
        const Offset(100, 100),
      );
      final tokenB = h.graph.beginNodePresentationDragForId(
        h.idB,
        const Offset(200, 200),
      );
      h.scene.addPlacementHandoffGraphIds({h.idA});

      final algorithm = _GatedAlgorithm();
      h.scene.scheduleLayoutHandoff(
        isClosed: () => false,
        algorithm: () => algorithm,
      );
      await _frame(tester);

      expect(algorithm.requests, 1);
      expect(h.scene.awaitingLayoutOutcome, isTrue);
      expect(h.scene.placementHandoffGraphIds, isEmpty);
      expect(h.tokenOf(h.idA), tokenA);

      algorithm.release();
      await _settle(tester, h.graph);

      expect(h.graph.scene.layoutOutcome, isA<GraphLayoutOutcomeSucceeded>());
      expect(h.tokenOf(h.idA), isNull);
      expect(h.tokenOf(h.idB), tokenB);
    });

    testWidgets('recovery after rebuild releases every active token', (
      tester,
    ) async {
      final h = await _mount(tester);
      h.graph.beginNodePresentationDragForId(h.idA, const Offset(100, 100));
      h.graph.beginNodePresentationDragForId(h.idB, const Offset(200, 200));
      expect(h.scene.activePresentationReleaseTokens(), hasLength(2));
      h.scene.scheduleLayoutRecoveryAfterRebuild = true;

      final algorithm = _GatedAlgorithm();
      h.scene.scheduleLayoutHandoff(
        isClosed: () => false,
        algorithm: () => algorithm,
      );
      await _frame(tester);

      expect(h.scene.scheduleLayoutRecoveryAfterRebuild, isFalse);
      expect(h.tokenOf(h.idA), isNotNull);

      algorithm.release();
      await _settle(tester, h.graph);

      expect(h.tokenOf(h.idA), isNull);
      expect(h.tokenOf(h.idB), isNull);
    });

    testWidgets('a superseded hand-off callback is dropped', (tester) async {
      final h = await _mount(tester);
      final stale = _GatedAlgorithm();
      final fresh = _GatedAlgorithm();

      h.scene
        ..scheduleLayoutHandoff(isClosed: () => false, algorithm: () => stale)
        ..scheduleLayoutHandoff(isClosed: () => false, algorithm: () => fresh);
      await _frame(tester);

      expect(stale.requests, 0);
      expect(fresh.requests, 1);

      fresh.release();
      await _settle(tester, h.graph);
    });

    testWidgets('a hand-off scheduled before close never requests layout', (
      tester,
    ) async {
      final h = await _mount(tester);
      h.graph.beginNodePresentationDragForId(h.idA, const Offset(100, 100));
      h.scene.addPlacementHandoffGraphIds({h.idA});
      var closed = false;
      final algorithm = _GatedAlgorithm();

      h.scene.scheduleLayoutHandoff(
        isClosed: () => closed,
        algorithm: () => algorithm,
      );
      closed = true;
      await _frame(tester);

      expect(algorithm.requests, 0);
      expect(h.scene.awaitingLayoutOutcome, isFalse);
      expect(h.scene.placementHandoffGraphIds, {h.idA});
      expect(h.tokenOf(h.idA), isNotNull);
    });
  });
}
