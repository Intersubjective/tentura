import 'dart:ui';

import 'package:force_directed_graphview/src/layout_algorithm/graph_layout_algorithm.dart';
import 'package:force_directed_graphview/src/layout_algorithm/graph_layout_request.dart';
import 'package:force_directed_graphview/src/layout_algorithm/scene_layout_algorithm.dart';
import 'package:force_directed_graphview/src/model/edge.dart';
import 'package:force_directed_graphview/src/model/graph_layout.dart';
import 'package:force_directed_graphview/src/model/node.dart';
import 'package:force_directed_graphview/src/scene/graph_ids.dart';
import 'package:force_directed_graphview/src/scene/scene_geometry.dart';
import 'package:force_directed_graphview/src/scene/scene_layout.dart';

/// Wraps a legacy [GraphLayoutAlgorithm] as [SceneLayoutAlgorithm].
///
/// Captures [nodes], [edges], and ID resolvers once per adapter instance.
/// Maps [NodeBase.pinned] to [GraphLayoutNode.simulationFixed] when building
/// requests elsewhere; positions are converted through [nodeIdOf].
final class LegacyGraphLayoutAlgorithmAdapter implements SceneLayoutAlgorithm {
  LegacyGraphLayoutAlgorithmAdapter({
    required GraphLayoutAlgorithm delegate,
    required Set<NodeBase> nodes,
    required Set<EdgeBase> edges,
    required GraphNodeId Function(NodeBase node) nodeIdOf,
    required GraphEdgeId Function(EdgeBase edge) edgeIdOf,
  })  : _delegate = delegate,
        _nodes = Set<NodeBase>.of(nodes),
        _edges = Set<EdgeBase>.of(edges),
        _nodeIdOf = nodeIdOf,
        _edgeIdOf = edgeIdOf {
    _nodesById = {
      for (final node in _nodes) nodeIdOf(node): node,
    };
  }

  final GraphLayoutAlgorithm _delegate;
  final Set<NodeBase> _nodes;
  final Set<EdgeBase> _edges;
  final GraphNodeId Function(NodeBase node) _nodeIdOf;
  final GraphEdgeId Function(EdgeBase edge) _edgeIdOf;
  late final Map<GraphNodeId, NodeBase> _nodesById;

  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) async* {
    _assertRequestMatchesSnapshot(request);

    final size = Size(request.canvasSize.width, request.canvasSize.height);
    final existingLayout = _legacyLayoutFromPrevious(request.previous);

    final stream = existingLayout == null
        ? _delegate.layout(nodes: _nodes, edges: _edges, size: size)
        : _delegate.relayout(
            existingLayout: existingLayout,
            nodes: _nodes,
            edges: _edges,
            size: size,
          );

    GraphLayoutFrame? last;
    var sequence = 0;

    await for (final graphLayout in stream) {
      final frame = GraphLayoutFrame(
        ticket: request.ticket,
        sequence: sequence++,
        positions: _scenePositionsFromLayout(graphLayout, request),
        isTerminal: false,
      );
      yield frame;
      last = frame;
    }

    if (last == null) {
      throw StateError('Legacy layout stream completed without frames');
    }

    yield GraphLayoutFrame(
      ticket: request.ticket,
      sequence: sequence,
      positions: last.positions,
      isTerminal: true,
    );
  }

  void _assertRequestMatchesSnapshot(GraphLayoutRequest request) {
    if (request.nodesById.length != _nodes.length) {
      throw ArgumentError('GraphLayoutRequest node count does not match snapshot');
    }
    if (request.edgesById.length != _edges.length) {
      throw ArgumentError('GraphLayoutRequest edge count does not match snapshot');
    }
    for (final edge in _edges) {
      final edgeId = _edgeIdOf(edge);
      final spec = request.edgesById[edgeId];
      if (spec == null) {
        throw ArgumentError('GraphLayoutRequest missing edge $edgeId');
      }
    }
    for (final node in _nodes) {
      final id = _nodeIdOf(node);
      final spec = request.nodesById[id];
      if (spec == null) {
        throw ArgumentError('GraphLayoutRequest missing node $id');
      }
      if (spec.simulationFixed != node.pinned) {
        throw ArgumentError(
          'simulationFixed for $id must match NodeBase.pinned (${node.pinned})',
        );
      }
    }
  }

  GraphLayout? _legacyLayoutFromPrevious(SceneLayout? previous) {
    if (previous == null) {
      return null;
    }
    final builder = GraphLayoutBuilder(nodes: _nodes);
    for (final node in _nodes) {
      final id = _nodeIdOf(node);
      final point = previous.positions[id];
      if (point == null) {
        throw ArgumentError('previous layout missing position for $id');
      }
      builder.setNodePosition(node, Offset(point.x, point.y));
    }
    return builder.build();
  }

  Map<GraphNodeId, ScenePoint> _scenePositionsFromLayout(
    GraphLayout layout,
    GraphLayoutRequest request,
  ) {
    final positions = <GraphNodeId, ScenePoint>{};
    for (final id in request.nodeIds) {
      final node = _nodesById[id];
      if (node == null) {
        throw StateError('Missing node for layout id $id');
      }
      final offset = layout.getPositionOrNull(node);
      if (offset == null) {
        throw StateError('Legacy layout missing position for $id');
      }
      positions[id] = ScenePoint(x: offset.dx, y: offset.dy);
    }
    return positions;
  }
}
