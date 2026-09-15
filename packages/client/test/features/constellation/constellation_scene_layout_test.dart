import 'dart:ui' show Size;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/domain/constellation_path_resolution.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
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

    test('forgetPriorHintNodeIds participates in equality', () {
      final withForget = ConstellationSceneLayoutAlgorithm(
        egoId: egoId,
        paths: paths,
        keptPeerIds: const {'peer-a'},
        maxHops: 3,
        visibleRequestsByAuthor: const {},
        egoOwnRequestIds: const {},
        forgetPriorHintNodeIds: const {'peer-a'},
      );
      expect(withForget, isNot(equals(algorithm)));
      expect(
        withForget,
        equals(
          ConstellationSceneLayoutAlgorithm(
            egoId: egoId,
            paths: paths,
            keptPeerIds: const {'peer-a'},
            maxHops: 3,
            visibleRequestsByAuthor: const {},
            egoOwnRequestIds: const {},
            forgetPriorHintNodeIds: const {'peer-a'},
          ),
        ),
      );
    });

    test('forgetPriorHintNodeIds skips previous-position inertia', () async {
      final first = await layoutPositionsOnce(
        algorithm,
        nodes: {egoNode, peerNode},
        edges: const {},
        canvasSize: const Size(4200, 4200),
      );
      final ignoring = ConstellationSceneLayoutAlgorithm(
        egoId: egoId,
        paths: paths,
        keptPeerIds: const {'peer-a'},
        maxHops: 3,
        visibleRequestsByAuthor: const {},
        egoOwnRequestIds: const {},
        forgetPriorHintNodeIds: const {'peer-a'},
      );
      final farPrevious = sceneLayoutFromPositions({
        tenturaGraphNodeId(egoNode): first[tenturaGraphNodeId(egoNode)]!,
        tenturaGraphNodeId(peerNode): ScenePoint(x: 500, y: 500),
      });
      final keptFar = await layoutPositionsOnce(
        algorithm,
        nodes: {egoNode, peerNode},
        edges: const {},
        previous: farPrevious,
        canvasSize: const Size(4200, 4200),
      );
      final forgotFar = await layoutPositionsOnce(
        ignoring,
        nodes: {egoNode, peerNode},
        edges: const {},
        previous: farPrevious,
        canvasSize: const Size(4200, 4200),
      );
      expect(keptFar[tenturaGraphNodeId(peerNode)]!.x, closeTo(500, 1));
      expect(
        forgotFar[tenturaGraphNodeId(peerNode)]!.x,
        isNot(closeTo(500, 1)),
      );
    });

    test(
      'forgotten prior centre seed reflows request near author, not ego',
      () async {
        final requestPaths = resolveConstellationPaths(
          egoId: egoId,
          visiblePeerIds: const {'peer-a'},
          holderIds: {egoId, 'peer-a'},
          edges: const [(src: egoId, dst: 'peer-a', tier: 1)],
        );
        final requestNode = FieldRequestNode(
          request: const ConstellationRequest(
            id: 'req-1',
            authorId: 'peer-a',
            title: 'Need tools',
            status: 0,
          ),
        );
        final withRequest = ConstellationSceneLayoutAlgorithm(
          egoId: egoId,
          paths: requestPaths,
          keptPeerIds: const {'peer-a'},
          maxHops: 3,
          visibleRequestsByAuthor: const {
            'peer-a': ['req-1'],
          },
          egoOwnRequestIds: const {},
          forgetPriorHintNodeIds: const {'req-1'},
        );
        final baseline = await layoutPositionsOnce(
          withRequest,
          nodes: {egoNode, peerNode, requestNode},
          edges: const {},
          canvasSize: const Size(4200, 4200),
        );
        final ego = baseline[tenturaGraphNodeId(egoNode)]!;
        final baselineRequest = baseline[tenturaGraphNodeId(requestNode)]!;
        expect(
          (Offset(baselineRequest.x, baselineRequest.y) -
                  Offset(ego.x, ego.y))
              .distance,
          greaterThan(40),
          reason: 'baseline auto-layout must not seat request on ego',
        );
        final centreSeed = ScenePoint(x: ego.x, y: ego.y);
        final previous = sceneLayoutFromPositions({
          tenturaGraphNodeId(egoNode): ego,
          tenturaGraphNodeId(peerNode):
              baseline[tenturaGraphNodeId(peerNode)]!,
          tenturaGraphNodeId(requestNode): centreSeed,
        });
        final positions = await layoutPositionsOnce(
          withRequest,
          nodes: {egoNode, peerNode, requestNode},
          edges: const {},
          previous: previous,
          canvasSize: const Size(4200, 4200),
        );
        final author = positions[tenturaGraphNodeId(peerNode)]!;
        final request = positions[tenturaGraphNodeId(requestNode)]!;
        expect(
          (Offset(request.x, request.y) - Offset(ego.x, ego.y)).distance,
          greaterThan(40),
        );
        expect(
          (Offset(request.x, request.y) - Offset(author.x, author.y)).distance,
          lessThan(150),
        );
        expect(request.x, closeTo(baselineRequest.x, 1));
        expect(request.y, closeTo(baselineRequest.y, 1));
      },
    );
  });

  group('constellation graph reconciliation', () {
    test('reconcileTopology preserves camera and replaces payload by id', () {
      final controller = testGraphController();
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
