import 'package:meta/meta.dart';

import 'package:force_directed_graphview/src/scene/graph_ids.dart';
import 'package:force_directed_graphview/src/scene/graph_layout_ticket.dart';
import 'package:force_directed_graphview/src/scene/graph_presentation_token.dart';
import 'package:force_directed_graphview/src/scene/scene_collections.dart';
import 'package:force_directed_graphview/src/scene/scene_geometry.dart';

/// Binds a presentation override to a layout ticket for terminal handoff.
@immutable
final class GraphPresentationHold {
  const GraphPresentationHold({
    required this.token,
    required this.ticket,
  });

  final GraphPresentationToken token;
  final GraphLayoutTicket ticket;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphPresentationHold &&
          token == other.token &&
          ticket == other.ticket;

  @override
  int get hashCode => Object.hash(token, ticket);
}

/// Transient presentation: overrides, paint order, and layout holds.
@immutable
final class ScenePresentation {
  ScenePresentation._({
    required Map<GraphNodeId, ScenePoint> overrides,
    required List<GraphNodeId> paintOrder,
    required Map<GraphNodeId, GraphPresentationHold> holds,
  })  : overrides = unmodifiableScenePointMap(overrides),
        paintOrder = unmodifiableGraphNodeIdList(paintOrder),
        holds = Map<GraphNodeId, GraphPresentationHold>.unmodifiable(holds);

  /// Defensively copies all collections.
  factory ScenePresentation({
    Map<GraphNodeId, ScenePoint> overrides = const {},
    List<GraphNodeId> paintOrder = const [],
    Map<GraphNodeId, GraphPresentationHold> holds = const {},
  }) {
    final holdCopy = <GraphNodeId, GraphPresentationHold>{};
    for (final entry in holds.entries) {
      assertNonEmptyGraphId(entry.key, 'holds key');
      holdCopy[entry.key] = entry.value;
    }
    return ScenePresentation._(
      overrides: copyValidatedScenePointMap(overrides),
      paintOrder: paintOrder,
      holds: holdCopy,
    );
  }

  final Map<GraphNodeId, ScenePoint> overrides;
  final List<GraphNodeId> paintOrder;
  final Map<GraphNodeId, GraphPresentationHold> holds;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScenePresentation &&
          _positionsEqual(overrides, other.overrides) &&
          _listEquals(paintOrder, other.paintOrder) &&
          _holdsEqual(holds, other.holds);

  @override
  int get hashCode => Object.hash(
        Object.hashAllUnordered(overrides.entries),
        Object.hashAll(paintOrder),
        Object.hashAllUnordered(holds.entries),
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

bool _listEquals(List<GraphNodeId> a, List<GraphNodeId> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

bool _holdsEqual(
  Map<GraphNodeId, GraphPresentationHold> a,
  Map<GraphNodeId, GraphPresentationHold> b,
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
