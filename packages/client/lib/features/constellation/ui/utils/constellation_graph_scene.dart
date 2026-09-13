import 'package:force_directed_graphview/force_directed_graphview.dart';

import '../../../graph/domain/entity/edge_details.dart';
import '../../../graph/domain/entity/node_details.dart';
import '../../../graph/ui/utils/graph_scene_ids.dart';
import '../../domain/entity/constellation_anchor.dart';

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

GraphNodeId constellationGraphNodeIdForTarget(ConstellationAnchorTarget target) {
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

/// Resolves the semantic edge id registered in [knownEdgeIds].
GraphEdgeId constellationEdgeIdForEdge(
  EdgeDetails edge,
  Iterable<GraphEdgeId> knownEdgeIds,
) {
  final pairSuffix =
      '${tenturaGraphNodeId(edge.source)}->${tenturaGraphNodeId(edge.destination)}';
  for (final id in knownEdgeIds) {
    if (id.endsWith(pairSuffix)) {
      return id;
    }
  }
  return tenturaGraphEdgeId(edge);
}
