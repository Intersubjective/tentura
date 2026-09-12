import 'package:meta/meta.dart';

import 'package:force_directed_graphview/src/scene/graph_ids.dart';
import 'package:force_directed_graphview/src/scene/graph_layout_ticket.dart';
import 'package:force_directed_graphview/src/scene/scene_geometry.dart';
import 'package:force_directed_graphview/src/scene/scene_layout.dart';

/// Layout input for one node: stable [id], bounds, and simulation hint.
@immutable
final class GraphLayoutNode {
  const GraphLayoutNode({
    required this.id,
    required this.size,
    this.simulationFixed = false,
  });

  final GraphNodeId id;
  final SceneSize size;

  /// When true, force-directed steps must not move this node ([NodeBase.pinned]
  /// in the legacy adapter).
  final bool simulationFixed;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphLayoutNode &&
          id == other.id &&
          size == other.size &&
          simulationFixed == other.simulationFixed;

  @override
  int get hashCode => Object.hash(id, size, simulationFixed);
}

/// Layout input for one edge: stable [id] and directed endpoints.
@immutable
final class GraphLayoutEdge {
  const GraphLayoutEdge({
    required this.id,
    required this.sourceId,
    required this.destinationId,
  });

  final GraphEdgeId id;
  final GraphNodeId sourceId;
  final GraphNodeId destinationId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphLayoutEdge &&
          id == other.id &&
          sourceId == other.sourceId &&
          destinationId == other.destinationId;

  @override
  int get hashCode => Object.hash(id, sourceId, destinationId);
}

/// Immutable ID-keyed layout specification for [SceneLayoutAlgorithm].
@immutable
final class GraphLayoutRequest {
  GraphLayoutRequest._({
    required this.ticket,
    required this.canvasSize,
    required Map<GraphNodeId, GraphLayoutNode> nodesById,
    required Map<GraphEdgeId, GraphLayoutEdge> edgesById,
    this.previous,
  })  : nodesById = _copyLayoutNodes(nodesById),
        edgesById = _copyLayoutEdges(edgesById);

  /// Validates topology references and defensively copies maps.
  factory GraphLayoutRequest({
    required GraphLayoutTicket ticket,
    required SceneSize canvasSize,
    required Map<GraphNodeId, GraphLayoutNode> nodesById,
    required Map<GraphEdgeId, GraphLayoutEdge> edgesById,
    SceneLayout? previous,
  }) {
    final nodes = _copyLayoutNodes(nodesById);
    final edges = _copyLayoutEdges(edgesById);
    for (final edge in edges.values) {
      if (!nodes.containsKey(edge.sourceId)) {
        throw ArgumentError(
          'edge ${edge.id} references missing source ${edge.sourceId}',
        );
      }
      if (!nodes.containsKey(edge.destinationId)) {
        throw ArgumentError(
          'edge ${edge.id} references missing destination ${edge.destinationId}',
        );
      }
    }
    return GraphLayoutRequest._(
      ticket: ticket,
      canvasSize: canvasSize,
      nodesById: nodes,
      edgesById: edges,
      previous: previous,
    );
  }

  final GraphLayoutTicket ticket;
  final SceneSize canvasSize;
  final Map<GraphNodeId, GraphLayoutNode> nodesById;
  final Map<GraphEdgeId, GraphLayoutEdge> edgesById;

  /// Last accepted layout hint for relayout; never a mutable simulation map.
  final SceneLayout? previous;

  Set<GraphNodeId> get nodeIds => nodesById.keys.toSet();
}

Map<GraphNodeId, GraphLayoutNode> _copyLayoutNodes(
  Map<GraphNodeId, GraphLayoutNode> source,
) {
  final copy = <GraphNodeId, GraphLayoutNode>{};
  for (final entry in source.entries) {
    assertNonEmptyGraphId(entry.key, 'nodeId');
    final node = entry.value;
    if (node.id != entry.key) {
      throw ArgumentError(
        'node map key ${entry.key} does not match node.id ${node.id}',
      );
    }
    copy[entry.key] = node;
  }
  return Map<GraphNodeId, GraphLayoutNode>.unmodifiable(copy);
}

Map<GraphEdgeId, GraphLayoutEdge> _copyLayoutEdges(
  Map<GraphEdgeId, GraphLayoutEdge> source,
) {
  final copy = <GraphEdgeId, GraphLayoutEdge>{};
  for (final entry in source.entries) {
    assertNonEmptyGraphId(entry.key, 'edgeId');
    final edge = entry.value;
    if (edge.id != entry.key) {
      throw ArgumentError(
        'edge map key ${entry.key} does not match edge.id ${edge.id}',
      );
    }
    copy[entry.key] = edge;
  }
  return Map<GraphEdgeId, GraphLayoutEdge>.unmodifiable(copy);
}
