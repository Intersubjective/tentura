import 'package:force_directed_graphview/force_directed_graphview.dart';

import '../../domain/entity/edge_details.dart';
import '../../domain/entity/node_details.dart';

/// Prefixes for injective [GraphNodeId] encoding at the Tentura UI boundary.
abstract final class TenturaGraphNodeKind {
  static const user = 'u';
  static const beacon = 'b';
  static const fieldPerson = 'fp';
  static const fieldRequest = 'fr';
  static const genealogyUser = 'gu';
  static const genealogyDeleted = 'gd';
}

/// Stable scene node id: kind + domain layout key (not render payload identity).
GraphNodeId tenturaGraphNodeId(NodeDetails node) => switch (node) {
  UserNode() => '${TenturaGraphNodeKind.user}:${node.id}',
  BeaconNode() => '${TenturaGraphNodeKind.beacon}:${node.id}',
  FieldPersonNode() => '${TenturaGraphNodeKind.fieldPerson}:${node.id}',
  FieldRequestNode() => '${TenturaGraphNodeKind.fieldRequest}:${node.id}',
  GenealogyUserNode() => '${TenturaGraphNodeKind.genealogyUser}:${node.nodeKey}',
  GenealogyDeletedNode() =>
    '${TenturaGraphNodeKind.genealogyDeleted}:${node.nodeKey}',
};

/// Domain layout id used by radial/DAG/constellation pure layout helpers.
String tenturaLayoutDomainId(GraphNodeId graphNodeId) {
  final separator = graphNodeId.indexOf(':');
  if (separator <= 0 || separator >= graphNodeId.length - 1) {
    throw ArgumentError.value(
      graphNodeId,
      'graphNodeId',
      'expected kind:domainKey encoding',
    );
  }
  return graphNodeId.substring(separator + 1);
}

/// Directed trust/forwards/genealogy edge identity (style-independent).
GraphEdgeId tenturaGraphEdgeId(EdgeDetails edge) {
  final sourceId = tenturaGraphNodeId(edge.source);
  final destinationId = tenturaGraphNodeId(edge.destination);
  return 'd:$sourceId->$destinationId';
}

/// Builds a bijection from layout domain id to graph node id for one request.
Map<String, GraphNodeId> tenturaGraphIdsByDomainId(
  Iterable<GraphNodeId> graphNodeIds,
) {
  final byDomain = <String, GraphNodeId>{};
  for (final graphId in graphNodeIds) {
    final domainId = tenturaLayoutDomainId(graphId);
    final existing = byDomain[domainId];
    if (existing != null && existing != graphId) {
      throw ArgumentError(
        'duplicate layout domain id $domainId for graph ids $existing and $graphId',
      );
    }
    byDomain[domainId] = graphId;
  }
  return byDomain;
}

GraphController<NodeDetails, EdgeDetails> createTenturaGraphController() =>
    GraphController(
      nodeIdOf: tenturaGraphNodeId,
      edgeIdOf: tenturaGraphEdgeId,
      nodeSizeOf: (node) => node.size,
      nodeSimulationFixedOf: (node) => node.pinned,
      edgeSourceOf: (edge) => edge.source,
      edgeDestinationOf: (edge) => edge.destination,
    );
