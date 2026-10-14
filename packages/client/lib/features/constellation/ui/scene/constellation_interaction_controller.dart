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

  String? draggingNodeId;
  bool suppressLateGestureEnd = false;

  final Set<GraphNodeId> placementClusterGraphIds = {};
  final Map<GraphNodeId, ConstellationAnchorTarget> placementClusterTargets =
      {};
  final Map<GraphNodeId, Offset> clusterStartCentres = {};

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
    final parentStart = clusterStartCentres[parentGraphId];
    if (parentStart == null) {
      return;
    }
    final limited = constellationLimitClusterDelta(
      parentStart: (x: parentStart.dx, y: parentStart.dy),
      proposedParent: (x: sceneCentre.dx, y: sceneCentre.dy),
      companionStarts: companionClusterStarts(parentGraphId),
    );
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
    if (parentStart == null) {
      return proposed;
    }
    final limited = constellationLimitClusterDelta(
      parentStart: (x: parentStart.dx, y: parentStart.dy),
      proposedParent: (x: proposed.dx, y: proposed.dy),
      companionStarts: companionClusterStarts(parentGraphId),
    );
    return Offset(
      parentStart.dx + limited.x,
      parentStart.dy + limited.y,
    );
  }

  void beginClusterDragPresentation(
    ConstellationAnchorTarget target, {
    required ConstellationField? field,
    required ConstellationComposedPresentation? composition,
    required List<ConstellationAnchor> fallbackAnchors,
  }) {
    clearPlacementClusterState();
    _beginDragPresentation(target);
    final parentGraphId = constellationGraphNodeIdForTarget(target);
    placementClusterGraphIds.add(parentGraphId);
    placementClusterTargets[parentGraphId] = target;
    _recordClusterStartCentre(parentGraphId, fallbackAnchors);
    if (target.kind == ConstellationAnchorTargetKind.person) {
      _addPersonDragCompanions(
        authorId: target.id,
        field: field,
        composition: composition,
        fallbackAnchors: fallbackAnchors,
      );
    }
  }

  void _addPersonDragCompanions({
    required String authorId,
    required ConstellationField? field,
    required ConstellationComposedPresentation? composition,
    required List<ConstellationAnchor> fallbackAnchors,
  }) {
    if (field == null || composition == null) {
      return;
    }
    final pinnedBeaconIds = constellationPinnedBeaconIds(
      composition.anchorOverlay.anchors,
    );
    final satellites = constellationAuthorSatellites(
      authorId: authorId,
      fieldRequests: field.requests,
      overlayPinnedRequests: composition.anchorOverlay.pinnedRequests,
      pinnedBeaconIds: pinnedBeaconIds,
    );
    final onGraphRequestIds = <String>{
      for (final graphId
          in _graphController.renderSnapshot.topology.nodesById.keys)
        if (graphId.startsWith('${TenturaGraphNodeKind.fieldRequest}:'))
          tenturaLayoutDomainId(graphId),
    };
    final companionIds = satellites.pinnedIds
        .intersection(_scene.displayedRequestIds)
        .intersection(onGraphRequestIds);
    for (final requestId in companionIds) {
      final companionTarget = ConstellationAnchorTarget.beacon(requestId);
      final graphId = constellationGraphNodeIdForTarget(companionTarget);
      if (_graphController.nodePayloadForId(graphId) == null) {
        continue;
      }
      placementClusterGraphIds.add(graphId);
      placementClusterTargets[graphId] = companionTarget;
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
  /// at the delta itself, a companion following it but stopping at the edges.
  Offset clusterCentreFor(
    GraphNodeId graphId,
    GraphNodeId parentGraphId,
    ConstellationPoint parentDelta,
  ) {
    final start = clusterStartCentres[graphId]!;
    if (graphId == parentGraphId) {
      return Offset(start.dx + parentDelta.x, start.dy + parentDelta.y);
    }
    final point = constellationCompanionPosition(
      companionStart: (x: start.dx, y: start.dy),
      parentDelta: parentDelta,
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
