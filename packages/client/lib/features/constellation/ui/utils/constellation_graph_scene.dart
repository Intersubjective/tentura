import 'package:force_directed_graphview/force_directed_graphview.dart';

import '../../../graph/domain/entity/edge_details.dart';
import '../../../graph/domain/entity/node_details.dart';
import '../../../graph/ui/utils/graph_scene_ids.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

/// Stable scene edge id including semantic [kindName] (parallel edges differ).
GraphEdgeId constellationSceneEdgeId({
  required String kindName,
  required NodeDetails source,
  required NodeDetails destination,
}) {
  final sourceId = tenturaGraphNodeId(source);
  final destinationId = tenturaGraphNodeId(destination);
  return 'c:$kindName:$sourceId->$destinationId';
}

GraphNodeId constellationGraphNodeIdForTarget(
  ConstellationAnchorTarget target,
) {
  return switch (target.kind) {
    ConstellationAnchorTargetKind.person =>
      '${TenturaGraphNodeKind.fieldPerson}:${target.id}',
    ConstellationAnchorTargetKind.beacon =>
      '${TenturaGraphNodeKind.fieldRequest}:${target.id}',
  };
}

GraphNodeId constellationGraphNodeIdForDomain(String domainNodeId) {
  return '${TenturaGraphNodeKind.fieldPerson}:$domainNodeId';
}

/// Resolves the scene edge id registered in [knownEdgeIds] for the
/// `'src->dst#kind'` [EdgeDetails.semanticId] of [edge].
GraphEdgeId constellationEdgeIdForEdge(
  EdgeDetails edge,
  Iterable<GraphEdgeId> knownEdgeIds,
) {
  final semanticId = edge.semanticId;
  final separator = semanticId.lastIndexOf('#');
  if (separator >= 0) {
    final sceneId =
        'c:${semanticId.substring(separator + 1)}:'
        '${semanticId.substring(0, separator)}';
    if (knownEdgeIds.contains(sceneId)) {
      return sceneId;
    }
  }
  return tenturaGraphEdgeId(edge);
}
