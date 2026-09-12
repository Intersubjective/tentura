import 'package:force_directed_graphview/src/scene/graph_ids.dart';
import 'package:force_directed_graphview/src/scene/scene_geometry.dart';

Map<GraphNodeId, ScenePoint> unmodifiableScenePointMap(
  Map<GraphNodeId, ScenePoint> source,
) {
  final copy = <GraphNodeId, ScenePoint>{};
  for (final entry in source.entries) {
    assertNonEmptyGraphId(entry.key, 'nodeId');
    copy[entry.key] = entry.value;
  }
  return Map<GraphNodeId, ScenePoint>.unmodifiable(copy);
}

Map<GraphNodeId, ScenePoint> copyValidatedScenePointMap(
  Map<GraphNodeId, ScenePoint> source,
) {
  final copy = <GraphNodeId, ScenePoint>{};
  for (final entry in source.entries) {
    assertNonEmptyGraphId(entry.key, 'nodeId');
    copy[entry.key] = entry.value;
  }
  return copy;
}

List<GraphNodeId> unmodifiableGraphNodeIdList(Iterable<GraphNodeId> source) {
  final copy = <GraphNodeId>[];
  for (final id in source) {
    assertNonEmptyGraphId(id, 'nodeId');
    copy.add(id);
  }
  return List<GraphNodeId>.unmodifiable(copy);
}
