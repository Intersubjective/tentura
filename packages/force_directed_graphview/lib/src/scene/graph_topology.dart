import 'package:meta/meta.dart';

import 'package:force_directed_graphview/src/scene/graph_ids.dart';
import 'package:force_directed_graphview/src/scene/scene_geometry.dart';

/// One node in scene topology: stable [id], render [payload], and bounds.
@immutable
final class GraphSceneNode<N> {
  const GraphSceneNode({
    required this.id,
    required this.payload,
    required this.size,
    this.simulationFixed = false,
  });

  final GraphNodeId id;
  final N payload;
  final SceneSize size;
  final bool simulationFixed;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphSceneNode<N> &&
          id == other.id &&
          payload == other.payload &&
          size == other.size &&
          simulationFixed == other.simulationFixed;

  @override
  int get hashCode => Object.hash(id, payload, size, simulationFixed);
}

/// One directed edge in scene topology with a stable [id].
@immutable
final class GraphSceneEdge<E> {
  const GraphSceneEdge({
    required this.id,
    required this.sourceId,
    required this.destinationId,
    required this.payload,
  });

  final GraphEdgeId id;
  final GraphNodeId sourceId;
  final GraphNodeId destinationId;
  final E payload;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphSceneEdge<E> &&
          id == other.id &&
          sourceId == other.sourceId &&
          destinationId == other.destinationId &&
          payload == other.payload;

  @override
  int get hashCode => Object.hash(id, sourceId, destinationId, payload);
}

/// Immutable validated graph membership keyed by stable IDs.
@immutable
final class GraphTopology<N, E> {
  GraphTopology._({
    required Map<GraphNodeId, GraphSceneNode<N>> nodesById,
    required Map<GraphEdgeId, GraphSceneEdge<E>> edgesById,
  })  : nodesById = Map<GraphNodeId, GraphSceneNode<N>>.unmodifiable(nodesById),
        edgesById = Map<GraphEdgeId, GraphSceneEdge<E>>.unmodifiable(edgesById);

  /// Validates entries, rejects duplicate or empty IDs and missing endpoints.
  factory GraphTopology.fromEntries({
    required Iterable<GraphSceneNode<N>> nodes,
    required Iterable<GraphSceneEdge<E>> edges,
  }) {
    final nodeMap = <GraphNodeId, GraphSceneNode<N>>{};
    for (final node in nodes) {
      assertNonEmptyGraphId(node.id, 'node.id');
      if (nodeMap.containsKey(node.id)) {
        throw ArgumentError.value(
          node.id,
          'nodes',
          'duplicate node id',
        );
      }
      nodeMap[node.id] = node;
    }

    final edgeMap = <GraphEdgeId, GraphSceneEdge<E>>{};
    for (final edge in edges) {
      assertNonEmptyGraphId(edge.id, 'edge.id');
      assertNonEmptyGraphId(edge.sourceId, 'edge.sourceId');
      assertNonEmptyGraphId(edge.destinationId, 'edge.destinationId');
      if (edgeMap.containsKey(edge.id)) {
        throw ArgumentError.value(
          edge.id,
          'edges',
          'duplicate edge id',
        );
      }
      if (!nodeMap.containsKey(edge.sourceId)) {
        throw ArgumentError.value(
          edge.sourceId,
          'edge.sourceId',
          'missing endpoint node',
        );
      }
      if (!nodeMap.containsKey(edge.destinationId)) {
        throw ArgumentError.value(
          edge.destinationId,
          'edge.destinationId',
          'missing endpoint node',
        );
      }
      edgeMap[edge.id] = edge;
    }

    return GraphTopology._(nodesById: nodeMap, edgesById: edgeMap);
  }

  final Map<GraphNodeId, GraphSceneNode<N>> nodesById;
  final Map<GraphEdgeId, GraphSceneEdge<E>> edgesById;

  bool get isEmpty => nodesById.isEmpty && edgesById.isEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphTopology<N, E> &&
          _mapEquals(nodesById, other.nodesById) &&
          _mapEquals(edgesById, other.edgesById);

  @override
  int get hashCode => Object.hash(
        Object.hashAllUnordered(nodesById.entries),
        Object.hashAllUnordered(edgesById.entries),
      );
}

bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (a.length != b.length) {
    return false;
  }
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}
