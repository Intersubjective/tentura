import 'package:meta/meta.dart';

import 'package:force_directed_graphview/src/scene/graph_ids.dart';
import 'package:force_directed_graphview/src/scene/scene_collections.dart';
import 'package:force_directed_graphview/src/scene/scene_geometry.dart';

/// Displayed interpolation positions between accepted layout frames.
@immutable
final class SceneTransition {
  SceneTransition._(Map<GraphNodeId, ScenePoint> positions)
      : positions = unmodifiableScenePointMap(positions);

  factory SceneTransition({
    Map<GraphNodeId, ScenePoint> positions = const {},
  }) =>
      SceneTransition._(copyValidatedScenePointMap(positions));

  final Map<GraphNodeId, ScenePoint> positions;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SceneTransition && _positionsEqual(positions, other.positions);

  @override
  int get hashCode => Object.hashAllUnordered(positions.entries);
}

bool _positionsEqual(
  Map<GraphNodeId, ScenePoint> a,
  Map<GraphNodeId, ScenePoint> b,
) {
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
