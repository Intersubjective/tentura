import 'package:meta/meta.dart';

import 'package:force_directed_graphview/src/layout_algorithm/graph_layout_request.dart';
import 'package:force_directed_graphview/src/scene/graph_ids.dart';
import 'package:force_directed_graphview/src/scene/graph_layout_ticket.dart';
import 'package:force_directed_graphview/src/scene/scene_collections.dart';
import 'package:force_directed_graphview/src/scene/scene_geometry.dart';

/// One layout publication for an active [GraphLayoutTicket].
@immutable
final class GraphLayoutFrame {
  GraphLayoutFrame({
    required this.ticket,
    required this.sequence,
    required Map<GraphNodeId, ScenePoint> positions,
    required this.isTerminal,
  }) : positions = unmodifiableScenePointMap(positions);

  final GraphLayoutTicket ticket;
  final int sequence;
  final Map<GraphNodeId, ScenePoint> positions;
  final bool isTerminal;

  GraphLayoutFrame copyWith({
    GraphLayoutTicket? ticket,
    int? sequence,
    Map<GraphNodeId, ScenePoint>? positions,
    bool? isTerminal,
  }) =>
      GraphLayoutFrame(
        ticket: ticket ?? this.ticket,
        sequence: sequence ?? this.sequence,
        positions: positions ?? this.positions,
        isTerminal: isTerminal ?? this.isTerminal,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphLayoutFrame &&
          ticket == other.ticket &&
          sequence == other.sequence &&
          isTerminal == other.isTerminal &&
          _positionsEqual(positions, other.positions);

  @override
  int get hashCode =>
      Object.hash(ticket, sequence, isTerminal, Object.hashAllUnordered(positions.entries));
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

/// ID-keyed layout port consumed by the scene controller (M03+).
abstract interface class SceneLayoutAlgorithm {
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request);
}
