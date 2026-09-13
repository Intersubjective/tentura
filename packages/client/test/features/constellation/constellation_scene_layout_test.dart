import 'dart:ui' show Size;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/domain/constellation_path_resolution.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_graph_scene.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/utils/graph_scene_ids.dart';
import 'package:tentura/features/graph/ui/utils/tentura_layout_algorithms.dart';

import '../graph/scene_layout_test_support.dart';

void main() {
  const egoId = 'ego';
  final paths = resolveConstellationPaths(
    egoId: egoId,
    visiblePeerIds: const {'peer-a'},
    holderIds: {egoId, 'peer-a'},
    edges: const [],
  );

  final algorithm = ConstellationSceneLayoutAlgorithm(
    egoId: egoId,
    paths: paths,
    keptPeerIds: const {'peer-a'},
    maxHops: 3,
    visibleRequestsByAuthor: const {},
    egoOwnRequestIds: const {},
  );

  final egoNode = FieldPersonNode(
    person: Profile(id: egoId, displayName: 'Ego'),
    ring: 0,
    isKept: true,
  );
  final peerNode = FieldPersonNode(
    person: Profile(id: 'peer-a', displayName: 'Peer'),
    ring: 1,
    isKept: true,
  );

  group('ConstellationSceneLayoutAlgorithm', () {
    test('emits terminal id-keyed positions', () async {
      final positions = await layoutPositionsOnce(
        algorithm,
        nodes: {egoNode, peerNode},
        edges: const {},
        canvasSize: const Size(4200, 4200),
      );
      expect(positions[tenturaGraphNodeId(egoNode)], isNotNull);
      expect(positions[tenturaGraphNodeId(peerNode)], isNotNull);
    });

    test('payload refresh keeps positions when topology unchanged', () async {
      final first = await layoutPositionsOnce(
        algorithm,
        nodes: {egoNode, peerNode},
        edges: const {},
        canvasSize: const Size(4200, 4200),
      );
      final refreshedPeer = FieldPersonNode(
        person: Profile(id: 'peer-a', displayName: 'Peer renamed'),
        ring: 1,
        isKept: true,
      );
      final previous = sceneLayoutFromPositions(first);
      final second = await layoutPositionsOnce(
        algorithm,
        nodes: {egoNode, refreshedPeer},
        edges: const {},
        previous: previous,
        canvasSize: const Size(4200, 4200),
      );
      expect(second[tenturaGraphNodeId(refreshedPeer)], first[tenturaGraphNodeId(peerNode)]);
    });
  });

  group('constellation graph reconciliation', () {
    test('reconcileTopology preserves camera and replaces payload by id', () {
      final controller = testGraphController();
      controller.useLayoutAlgorithm(
        BoundSceneLayoutAlgorithm(algorithm),
      );
      final edge = EdgeDetails(
        source: egoNode,
        destination: peerNode,
        color: const Color(0),
        strokeWidth: 1,
      );
      controller.reconcileTopology(
        {egoNode, peerNode},
        {edge},
        requestLayout: false,
        layoutOnTopologyChange: false,
      );
      controller.requestSceneLayout();
      expect(controller.nodes.length, 2);

      final refreshedPeer = FieldPersonNode(
        person: Profile(id: 'peer-a', displayName: 'Renamed'),
        ring: 1,
        isKept: true,
      );
      controller.reconcileTopology(
        {egoNode, refreshedPeer},
        {edge},
        requestLayout: false,
        layoutOnTopologyChange: false,
      );
      final peer = controller.nodes.singleWhere((n) => n.id == 'peer-a') as FieldPersonNode;
      expect(peer.person.displayName, 'Renamed');
    });
  });

}
