import 'package:flutter/material.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../../graph/domain/entity/edge_details.dart';
import '../../../graph/domain/entity/node_details.dart';
import '../../../graph/ui/utils/graph_scene_ids.dart';
import '../../domain/constellation_anchor_composition.dart';
import '../../domain/constellation_drag_cluster.dart';
import '../../domain/constellation_layout.dart';
import '../../domain/entity/constellation_field.dart';
import '../utils/constellation_graph_scene.dart';
import 'constellation_scene_controller.dart';

/// Owns the drag-cluster state (dragged node, placement cluster and its start
/// centres) and drives the presentation tokens that follow a drag. It holds no
/// cubit state; the cubit passes what it needs per call.
class ConstellationInteractionController {
  ConstellationInteractionController(this._scene);

  final ConstellationSceneController _scene;

  GraphController<NodeDetails, EdgeDetails> get _graphController =>
      _scene.graphController;

  String? _draggingNodeId;

  String? get draggingNodeId => _draggingNodeId;

  set draggingNodeId(String? nodeId) {
    _draggingNodeId = nodeId;
  }

  bool suppressLateGestureEnd = false;

  final Set<GraphNodeId> placementClusterGraphIds = {};
  final Map<GraphNodeId, ConstellationAnchorTarget> placementClusterTargets =
      {};
  final Map<GraphNodeId, Offset> clusterStartCentres = {};

  /// The other selected nodes moved with the dragged one (group drag): they
  /// travel by the parent's own delta as one rigid group and are all written
  /// on the drop, pinned before or not. The rest of the cluster are a
  /// person's pinned Requests and Posts, which follow on their own as before.
  final Set<GraphNodeId> groupMemberGraphIds = {};

  /// The person each pinned Request or Post of the cluster belongs to: it
  /// follows that person's own movement, not the dragged node's.
  final Map<GraphNodeId, GraphNodeId> companionAuthorGraphIds = {};

  /// Entering `dragging` (ARCH §5.4): freezes the committed scene.
  void beginDragging(String nodeId) {
    suppressLateGestureEnd = false;
    draggingNodeId = nodeId;
    _scene.freeze();
  }

  void clearPlacementClusterState() {
    placementClusterGraphIds.clear();
    placementClusterTargets.clear();
    clusterStartCentres.clear();
    groupMemberGraphIds.clear();
    companionAuthorGraphIds.clear();
  }

  /// Forgets [graphId] as a part of the cluster.
  void removeFromCluster(GraphNodeId graphId) {
    placementClusterGraphIds.remove(graphId);
    placementClusterTargets.remove(graphId);
    clusterStartCentres.remove(graphId);
    groupMemberGraphIds.remove(graphId);
    companionAuthorGraphIds.remove(graphId);
  }

  /// The scene delta the cluster of [parentGraphId] moves by when the pointer
  /// proposes [proposed] for the parent; null when the parent has no start.
  ConstellationPoint? limitedClusterDelta(
    GraphNodeId parentGraphId,
    Offset proposed,
  ) {
    final parentStart = clusterStartCentres[parentGraphId];
    if (parentStart == null) {
      return null;
    }
    final start = (x: parentStart.dx, y: parentStart.dy);
    final proposedParent = (x: proposed.dx, y: proposed.dy);
    if (groupMemberGraphIds.isEmpty) {
      return constellationLimitClusterDelta(
        parentStart: start,
        proposedParent: proposedParent,
        companionStarts: companionClusterStarts(parentGraphId),
      );
    }
    return constellationLimitGroupDelta(
      parentStart: start,
      proposedParent: proposedParent,
      memberStarts: [
        for (final graphId in groupMemberGraphIds)
          if (clusterStartCentres[graphId] case final memberStart?)
            (x: memberStart.dx, y: memberStart.dy),
      ],
    );
  }

  void clearClusterPresentations() {
    for (final graphId in placementClusterGraphIds) {
      _graphController.clearPresentationForNodeId(graphId);
    }
    clearPlacementClusterState();
    _scene.clearPlacementHandoffGraphIds();
  }

  void updateDragPresentation(
    ConstellationAnchorTarget target,
    Offset sceneCentre,
  ) {
    final parentGraphId = constellationGraphNodeIdForTarget(target);
    if (placementClusterGraphIds.isEmpty) {
      _scene.updateSingleNodePresentation(parentGraphId, sceneCentre);
      return;
    }
    final limited = limitedClusterDelta(parentGraphId, sceneCentre);
    if (limited == null) {
      return;
    }
    final updates = <GraphPresentationToken, Offset>{};
    for (final graphId in placementClusterGraphIds) {
      final start = clusterStartCentres[graphId];
      if (start == null) {
        continue;
      }
      final centre = clusterCentreFor(graphId, parentGraphId, limited);
      final token = _graphController.activePresentationTokenForNode(graphId);
      if (token != null) {
        updates[token] = centre;
      } else {
        _graphController.beginNodePresentationDragForId(graphId, centre);
      }
    }
    if (updates.isNotEmpty) {
      _graphController.updateNodePresentationDrags(updates);
    }
  }

  Offset clampClusterDragPosition(
    ConstellationAnchorTarget? target,
    NodeDetails node,
    Offset proposed,
  ) {
    if (target == null || placementClusterGraphIds.isEmpty) {
      return proposed;
    }
    final parentGraphId = constellationGraphNodeIdForTarget(target);
    if (tenturaGraphNodeId(node) != parentGraphId) {
      return proposed;
    }
    final parentStart = clusterStartCentres[parentGraphId];
    final limited = limitedClusterDelta(parentGraphId, proposed);
    if (parentStart == null || limited == null) {
      return proposed;
    }
    return Offset(
      parentStart.dx + limited.x,
      parentStart.dy + limited.y,
    );
  }

  /// Starts the drag of [target] and of the nodes that travel with it: the
  /// other [group] members (the rest of a selection, already filtered to
  /// draggable nodes on the graph) and every person's pinned Requests and
  /// Posts.
  void beginClusterDragPresentation(
    ConstellationAnchorTarget target, {
    required ConstellationField? field,
    required ConstellationComposedPresentation? composition,
    required List<ConstellationAnchor> fallbackAnchors,
    Iterable<ConstellationAnchorTarget> group = const [],
  }) {
    clearPlacementClusterState();
    _beginDragPresentation(target);
    final parentGraphId = constellationGraphNodeIdForTarget(target);
    placementClusterGraphIds.add(parentGraphId);
    placementClusterTargets[parentGraphId] = target;
    _recordClusterStartCentre(parentGraphId, fallbackAnchors);
    final people = [
      if (target.kind == ConstellationAnchorTargetKind.person) target,
    ];
    for (final member in group) {
      final graphId = constellationGraphNodeIdForTarget(member);
      if (placementClusterGraphIds.contains(graphId) ||
          _graphController.nodePayloadForId(graphId) == null) {
        continue;
      }
      placementClusterTargets[graphId] = member;
      _recordClusterStartCentre(graphId, fallbackAnchors);
      final start = clusterStartCentres[graphId];
      if (start == null) {
        placementClusterTargets.remove(graphId);
        continue;
      }
      placementClusterGraphIds.add(graphId);
      groupMemberGraphIds.add(graphId);
      if (_graphController.activePresentationTokenForNode(graphId) == null) {
        _graphController.beginNodePresentationDragForId(graphId, start);
      }
      if (member.kind == ConstellationAnchorTargetKind.person) {
        people.add(member);
      }
    }
    for (final person in people) {
      _addPersonDragCompanions(
        authorId: person.id,
        field: field,
        composition: composition,
        fallbackAnchors: fallbackAnchors,
      );
    }
  }

  /// The pinned Requests and Posts of [authorId] drawn on the map now: they
  /// follow their author whenever the author is moved.
  Set<String> pinnedCompanionBeaconIds({
    required String authorId,
    required ConstellationField? field,
    required ConstellationComposedPresentation? composition,
  }) {
    if (field == null || composition == null) {
      return const {};
    }
    final pinnedBeaconIds = constellationPinnedBeaconIds(
      composition.anchorOverlay.anchors,
    );
    final satellites = constellationAuthorSatellites(
      authorId: authorId,
      fieldRequests: field.requests,
      overlayPinnedRequests: composition.anchorOverlay.pinnedRequests,
      pinnedBeaconIds: pinnedBeaconIds,
      fieldPosts: field.posts,
      pinnedPostIds: composition.pinnedPostIds,
    );
    // Requests and Posts share the field-beacon graph id kind.
    final onGraphRequestIds = <String>{
      for (final graphId
          in _graphController.renderSnapshot.topology.nodesById.keys)
        if (graphId.startsWith('${TenturaGraphNodeKind.fieldRequest}:'))
          tenturaLayoutDomainId(graphId),
    };
    return satellites.pinnedIds
        .intersection(_scene.displayedRequestIds)
        .intersection(onGraphRequestIds);
  }

  void _addPersonDragCompanions({
    required String authorId,
    required ConstellationField? field,
    required ConstellationComposedPresentation? composition,
    required List<ConstellationAnchor> fallbackAnchors,
  }) {
    final companionIds = pinnedCompanionBeaconIds(
      authorId: authorId,
      field: field,
      composition: composition,
    );
    for (final beaconId in companionIds) {
      final companionTarget = ConstellationAnchorTarget.beacon(beaconId);
      final graphId = constellationGraphNodeIdForTarget(companionTarget);
      // A selected Request or Post moves with the group rather than its
      // author.
      if (placementClusterGraphIds.contains(graphId) ||
          _graphController.nodePayloadForId(graphId) == null) {
        continue;
      }
      placementClusterGraphIds.add(graphId);
      placementClusterTargets[graphId] = companionTarget;
      companionAuthorGraphIds[graphId] = constellationGraphNodeIdForTarget(
        ConstellationAnchorTarget.person(authorId),
      );
      _recordClusterStartCentre(graphId, fallbackAnchors);
      final start = clusterStartCentres[graphId];
      if (start != null &&
          _graphController.activePresentationTokenForNode(graphId) == null) {
        _graphController.beginNodePresentationDragForId(graphId, start);
      }
    }
  }

  void _recordClusterStartCentre(
    GraphNodeId graphId,
    List<ConstellationAnchor> fallbackAnchors,
  ) {
    final point = _graphController.renderSnapshot.resolvePosition(graphId);
    if (point != null) {
      clusterStartCentres[graphId] = Offset(point.x, point.y);
      return;
    }
    final target = placementClusterTargets[graphId];
    if (target == null) {
      return;
    }
    for (final anchor in fallbackAnchors) {
      if (anchor.target != target) {
        continue;
      }
      final fallback = constellationV1AnchorToPoint(anchor.position);
      clusterStartCentres[graphId] = Offset(fallback.x, fallback.y);
      return;
    }
  }

  /// Where [graphId] rests when the parent moved by [parentDelta]: the parent
  /// at the delta itself, a group member with it as one rigid group, a
  /// companion following it but stopping at the edges.
  Offset clusterCentreFor(
    GraphNodeId graphId,
    GraphNodeId parentGraphId,
    ConstellationPoint parentDelta,
  ) {
    final start = clusterStartCentres[graphId]!;
    if (graphId == parentGraphId) {
      return Offset(start.dx + parentDelta.x, start.dy + parentDelta.y);
    }
    if (groupMemberGraphIds.contains(graphId)) {
      final point = constellationGroupMemberPosition(
        memberStart: (x: start.dx, y: start.dy),
        groupDelta: parentDelta,
      );
      return Offset(point.x, point.y);
    }
    // A pinned Request or Post moves as far as its own author did, which for
    // a group member that cannot travel the whole way is less than the
    // parent.
    final authorGraphId = companionAuthorGraphIds[graphId] ?? parentGraphId;
    final authorStart = clusterStartCentres[authorGraphId];
    var authorDelta = (x: 0.0, y: 0.0);
    if (authorGraphId == parentGraphId) {
      authorDelta = parentDelta;
    } else if (authorStart != null) {
      final author = clusterCentreFor(
        authorGraphId,
        parentGraphId,
        parentDelta,
      );
      authorDelta = (
        x: author.dx - authorStart.dx,
        y: author.dy - authorStart.dy,
      );
    }
    final point = constellationCompanionPosition(
      companionStart: (x: start.dx, y: start.dy),
      parentDelta: authorDelta,
    );
    return Offset(point.x, point.y);
  }

  Iterable<ConstellationPoint> companionClusterStarts(
    GraphNodeId parentGraphId,
  ) sync* {
    for (final graphId in placementClusterGraphIds) {
      if (graphId == parentGraphId) {
        continue;
      }
      final start = clusterStartCentres[graphId];
      if (start != null) {
        yield (x: start.dx, y: start.dy);
      }
    }
  }

  void _beginDragPresentation(ConstellationAnchorTarget target) {
    final graphId = constellationGraphNodeIdForTarget(target);
    final node = _graphController.nodePayloadForId(graphId);
    if (node == null) {
      return;
    }
    final point = _graphController.renderSnapshot.resolvePosition(graphId);
    if (point == null) {
      return;
    }
    if (_graphController.activePresentationTokenForNode(graphId) == null) {
      _graphController.beginNodePresentationDragForId(
        graphId,
        Offset(point.x, point.y),
      );
    }
  }
}
