import 'dart:ui' show Offset;

import 'package:force_directed_graphview/force_directed_graphview.dart';

GraphNodeId testIntNodeId(Node<int> node) => node.data.toString();

GraphEdgeId testIntEdgeId(Edge<Node<int>, Object?> edge) {
  final data = edge.data;
  if (data != null) {
    return data.toString();
  }
  return '${edge.source.hashCode}_${edge.destination.hashCode}';
}

GraphController<Node<int>, Edge<Node<int>, void>> testIntGraphController() =>
    GraphController(
      nodeIdOf: testIntNodeId,
      edgeIdOf: testIntEdgeId,
      nodeSizeOf: (node) => node.size,
      nodeSimulationFixedOf: (node) => node.pinned,
      edgeSourceOf: (edge) => edge.source,
      edgeDestinationOf: (edge) => edge.destination,
    );

GraphController<Node<int>, Edge<Node<int>, int>> testIntIntGraphController() =>
    GraphController(
      nodeIdOf: testIntNodeId,
      edgeIdOf: (edge) => edge.data.toString(),
      nodeSizeOf: (node) => node.size,
      nodeSimulationFixedOf: (node) => node.pinned,
      edgeSourceOf: (edge) => edge.source,
      edgeDestinationOf: (edge) => edge.destination,
    );

void testAddNode<E>(
  GraphController<Node<int>, E> controller,
  Node<int> node, {
  bool requestLayout = true,
}) {
  controller.reconcileTopology(
    {...controller.nodes, node},
    controller.edges,
    requestLayout: requestLayout,
  );
}

void testAddEdge<T>(
  GraphController<Node<int>, Edge<Node<int>, T>> controller,
  Edge<Node<int>, T> edge, {
  bool requestLayout = true,
}) {
  controller.reconcileTopology(
    controller.nodes,
    {...controller.edges, edge},
    requestLayout: requestLayout,
  );
}

void testRemoveNode<T>(
  GraphController<Node<int>, Edge<Node<int>, T>> controller,
  Node<int> node, {
  bool requestLayout = true,
}) {
  final nextNodes = controller.nodes.where((n) => n != node).toSet();
  final nextEdges = controller.edges
      .where(
        (edge) => edge.source != node && edge.destination != node,
      )
      .toSet();
  controller.reconcileTopology(
    nextNodes,
    nextEdges,
    requestLayout: requestLayout,
  );
}

void testRemoveEdge<T>(
  GraphController<Node<int>, Edge<Node<int>, T>> controller,
  Edge<Node<int>, T> edge, {
  bool requestLayout = true,
}) {
  controller.reconcileTopology(
    controller.nodes,
    controller.edges.where((e) => e != edge).toSet(),
    requestLayout: requestLayout,
  );
}

Offset testNodePosition(
  GraphController<Node<int>, dynamic> controller,
  Node<int> node,
) =>
    controller.getPositionForId(testIntNodeId(node));
