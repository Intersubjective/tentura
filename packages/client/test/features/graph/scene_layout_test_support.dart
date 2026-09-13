import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:force_directed_graphview/src/scene/graph_layout_ticket.dart';

import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/utils/graph_scene_ids.dart';

final Object _testLayoutTicketOwner = Object();

GraphController<NodeDetails, EdgeDetails<NodeDetails>> testGraphController() =>
    GraphController<NodeDetails, EdgeDetails<NodeDetails>>(
      nodeIdOf: tenturaGraphNodeId,
      edgeIdOf: tenturaGraphEdgeId,
    );

GraphLayoutRequest sceneLayoutRequest({
  required Set<NodeDetails> nodes,
  required Set<EdgeDetails<NodeDetails>> edges,
  SceneLayout? previous,
  Size canvasSize = const Size(500, 500),
}) {
  final nodesById = <GraphNodeId, GraphLayoutNode>{
    for (final node in nodes)
      tenturaGraphNodeId(node): GraphLayoutNode(
        id: tenturaGraphNodeId(node),
        size: SceneSize(width: node.size, height: node.size),
        simulationFixed: node.pinned,
      ),
  };
  final edgesById = <GraphEdgeId, GraphLayoutEdge>{
    for (final edge in edges)
      tenturaGraphEdgeId(edge): GraphLayoutEdge(
        id: tenturaGraphEdgeId(edge),
        sourceId: tenturaGraphNodeId(edge.source),
        destinationId: tenturaGraphNodeId(edge.destination),
      ),
  };
  return GraphLayoutRequest(
    ticket: mintGraphLayoutTicket(
      owner: _testLayoutTicketOwner,
      topologyRevision: 1,
      generation: 1,
    ),
    canvasSize: SceneSize(
      width: canvasSize.width,
      height: canvasSize.height,
    ),
    nodesById: nodesById,
    edgesById: edgesById,
    previous: previous,
  );
}

SceneLayout sceneLayoutFromPositions(
  Map<GraphNodeId, ScenePoint> positions,
) =>
    SceneLayout(
      ticket: mintGraphLayoutTicket(
        owner: _testLayoutTicketOwner,
        topologyRevision: 1,
        generation: 1,
      ),
      revision: 0,
      positions: positions,
    );

Future<Map<GraphNodeId, ScenePoint>> layoutPositionsOnce(
  SceneLayoutAlgorithm algorithm, {
  required Set<NodeDetails> nodes,
  required Set<EdgeDetails<NodeDetails>> edges,
  SceneLayout? previous,
  Size canvasSize = const Size(500, 500),
}) async {
  final request = sceneLayoutRequest(
    nodes: nodes,
    edges: edges,
    previous: previous,
    canvasSize: canvasSize,
  );
  final frame = await algorithm.layout(request).first;
  expect(frame.isTerminal, isTrue);
  return frame.positions;
}
