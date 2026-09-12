import 'package:meta/meta.dart';

import 'package:force_directed_graphview/src/scene/graph_ids.dart';
import 'package:force_directed_graphview/src/scene/graph_topology.dart';
import 'package:force_directed_graphview/src/scene/scene_collections.dart';
import 'package:force_directed_graphview/src/scene/scene_geometry.dart';
import 'package:force_directed_graphview/src/scene/scene_layout.dart';
import 'package:force_directed_graphview/src/scene/scene_presentation.dart';
import 'package:force_directed_graphview/src/scene/scene_transition.dart';

/// Immutable scene state captured for one paint, hit-test, or drag pass.
@immutable
final class GraphSceneSnapshot<N, E> {
  GraphSceneSnapshot._({
    required this.topology,
    this.layout,
    required this.presentation,
    this.transition,
    required Map<GraphNodeId, ScenePoint> seedPositions,
  }) : seedPositions = unmodifiableScenePointMap(seedPositions);

  factory GraphSceneSnapshot({
    required GraphTopology<N, E> topology,
    SceneLayout? layout,
    ScenePresentation? presentation,
    SceneTransition? transition,
    Map<GraphNodeId, ScenePoint> seedPositions = const {},
  }) =>
      GraphSceneSnapshot._(
        topology: topology,
        layout: layout,
        presentation: presentation ?? ScenePresentation(),
        transition: transition,
        seedPositions: copyValidatedScenePointMap(seedPositions),
      );

  final GraphTopology<N, E> topology;
  final SceneLayout? layout;
  final ScenePresentation presentation;
  final SceneTransition? transition;
  final Map<GraphNodeId, ScenePoint> seedPositions;

  /// Resolves display position for [id] when it is in [topology].
  ///
  /// Precedence: presentation override, transition, accepted layout, seed.
  ScenePoint? resolvePosition(GraphNodeId id) {
    if (!topology.nodesById.containsKey(id)) {
      return null;
    }
    return presentation.overrides[id] ??
        transition?.positions[id] ??
        layout?.positions[id] ??
        seedPositions[id];
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphSceneSnapshot<N, E> &&
          topology == other.topology &&
          layout == other.layout &&
          presentation == other.presentation &&
          transition == other.transition &&
          _positionsEqual(seedPositions, other.seedPositions);

  @override
  int get hashCode => Object.hash(
        topology,
        layout,
        presentation,
        transition,
        Object.hashAllUnordered(seedPositions.entries),
      );
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
