import 'package:force_directed_graphview/force_directed_graphview.dart';

/// Emits one terminal frame with fixed [positions] keyed by node data id string.
final class FixedSceneLayoutAlgorithm implements SceneLayoutAlgorithm {
  const FixedSceneLayoutAlgorithm(this.positions);

  final Map<String, ScenePoint> positions;

  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) async* {
    final resolved = <GraphNodeId, ScenePoint>{};
    for (final id in request.nodeIds) {
      resolved[id] = positions[id] ?? ScenePoint(x: 250, y: 250);
    }
    yield GraphLayoutFrame(
      ticket: request.ticket,
      sequence: 0,
      positions: resolved,
      isTerminal: true,
    );
  }
}
