import 'package:force_directed_graphview/force_directed_graphview.dart';

GraphNodeId testIntNodeId(NodeBase node) =>
    (node as Node<int>).data.toString();

GraphEdgeId testIntEdgeId(EdgeBase edge) {
  final typed = edge as Edge<Node<int>, Object?>;
  final data = typed.data;
  if (data != null) {
    return data.toString();
  }
  return '${typed.source.hashCode}_${typed.destination.hashCode}';
}

GraphController<Node<int>, Edge<Node<int>, void>> testIntGraphController() =>
    GraphController(
      nodeIdOf: testIntNodeId,
      edgeIdOf: testIntEdgeId,
    );

GraphController<Node<int>, Edge<Node<int>, int>> testIntIntGraphController() =>
    GraphController(
      nodeIdOf: testIntNodeId,
      edgeIdOf: (edge) => (edge as Edge<Node<int>, int>).data.toString(),
    );
