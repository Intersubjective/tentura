// While the composer is open, a person who is already on screen and has a
// confirmed pin is drawn at that pin, unless the viewer has moved them by hand
// or is holding them right now. Anchors are keyed by the person's id, the
// scene by the graph node id ('fp:<id>'); the two must be matched up.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura/features/constellation/ui/scene/constellation_scene_controller.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

const _nodeA = FieldPersonNode(
  person: Profile(id: 'a', displayName: 'A'),
  ring: 1,
  isKept: false,
);

const _pinnedAt = ConstellationAnchorPosition(
  xUnits: 0.45,
  yUnits: 0.45,
  coordinateSpaceVersion: 1,
);

final _pinAnchor = ConstellationAnchor(
  target: ConstellationAnchorTarget.person('a'),
  position: _pinnedAt,
  revision: ConstellationAnchorRevision(BigInt.one),
  placedAt: DateTime.utc(2026, 10, 9),
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

Future<ConstellationSceneController> _mount(WidgetTester tester) async {
  final scene = ConstellationSceneController();
  addTearDown(scene.graphController.dispose);
  scene.graphController.reconcileTopology(
    {_nodeA},
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
  for (var i = 0; i < 50; i++) {
    if (scene.graphController.scene.layoutOutcome
        is! GraphLayoutOutcomeRunning) {
      break;
    }
    await tester.pump(const Duration(milliseconds: 5));
  }
  return scene;
}

void _placeComposerNodes(
  ConstellationSceneController scene, {
  Map<String, Offset>? personPositions,
  Set<GraphNodeId> movedPersonIds = const {},
  GraphNodeId? heldPersonId,
}) {
  scene.placeComposerNodes(
    nodes: {_nodeA},
    previousNodeIds: {_nodeA.graphNodeId},
    viewerId: 'ego',
    placedPersonIds: <String>{},
    personPositions: personPositions ?? <String, Offset>{},
    movedPersonIds: movedPersonIds,
    heldPersonId: heldPersonId,
    confirmedAnchors: [_pinAnchor],
    draftCentre: Offset.zero,
  );
}

void main() {
  group('ConstellationSceneController.placeComposerNodes pinned people', () {
    testWidgets('an on-screen person with a confirmed pin is drawn at the pin', (
      tester,
    ) async {
      final scene = await _mount(tester);
      final pin = constellationV1AnchorToPoint(_pinnedAt);
      final pinOffset = Offset(pin.x, pin.y);
      final before = scene.graphController.getPositionOrNullForId('fp:a')!;
      expect((before - pinOffset).distance, greaterThan(20));

      _placeComposerNodes(scene);

      expect(
        (scene.graphController.getPositionOrNullForId('fp:a')! - pinOffset)
            .distance,
        lessThan(1),
      );
    });

    testWidgets('a person moved by hand stays where it was dropped', (
      tester,
    ) async {
      final scene = await _mount(tester);
      const dropped = Offset(700, 300);

      _placeComposerNodes(
        scene,
        personPositions: {'fp:a': dropped},
        movedPersonIds: {'fp:a'},
      );

      expect(
        (scene.graphController.getPositionOrNullForId('fp:a')! - dropped)
            .distance,
        lessThan(1),
      );
    });

    testWidgets('a person held under the pointer is left to the drag', (
      tester,
    ) async {
      final scene = await _mount(tester);
      final before = scene.graphController.getPositionOrNullForId('fp:a')!;

      _placeComposerNodes(scene, heldPersonId: 'fp:a');

      expect(
        scene.graphController.getPositionOrNullForId('fp:a'),
        before,
      );
    });
  });
}
