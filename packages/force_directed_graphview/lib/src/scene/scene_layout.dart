import 'package:meta/meta.dart';

import 'package:force_directed_graphview/src/scene/graph_ids.dart';
import 'package:force_directed_graphview/src/scene/graph_layout_ticket.dart';
import 'package:force_directed_graphview/src/scene/scene_collections.dart';
import 'package:force_directed_graphview/src/scene/scene_geometry.dart';

/// Last accepted layout positions for the active topology revision.
@immutable
final class SceneLayout {
  SceneLayout._({
    required this.ticket,
    required this.revision,
    required Map<GraphNodeId, ScenePoint> positions,
  }) : positions = unmodifiableScenePointMap(positions);

  /// Creates a defensive copy of [positions] with validated node IDs.
  factory SceneLayout({
    required GraphLayoutTicket ticket,
    required int revision,
    required Map<GraphNodeId, ScenePoint> positions,
  }) =>
      SceneLayout._(
        ticket: ticket,
        revision: revision,
        positions: copyValidatedScenePointMap(positions),
      );

  final GraphLayoutTicket ticket;
  final int revision;
  final Map<GraphNodeId, ScenePoint> positions;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SceneLayout &&
          ticket == other.ticket &&
          revision == other.revision &&
          _positionsEqual(positions, other.positions);

  @override
  int get hashCode => Object.hash(
        ticket,
        revision,
        Object.hashAllUnordered(positions.entries),
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
