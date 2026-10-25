import 'dart:ui' show Offset;

import 'package:force_directed_graphview/force_directed_graphview.dart';

import '../../domain/layout/constellation_tag_view_layout.dart';

/// The tag view draws its rings this much closer to the viewer than the Field
/// does, so a tag's members read as a group of their own.
const kConstellationTagViewRingScale = 0.8;

/// The tag view as a layout of the whole scene: [members] take their tag view
/// places, every other node stays where the Field had it ([fieldPositions]),
/// and a node in [followers] (a Request or Post) keeps its offset from the
/// node it follows, its author. Writes no anchors.
class ConstellationTagViewFieldLayoutAlgorithm implements SceneLayoutAlgorithm {
  const ConstellationTagViewFieldLayoutAlgorithm({
    required this.egoGraphId,
    required this.tagIds,
    required this.members,
    required this.fieldPositions,
    required this.followers,
  });

  final GraphNodeId egoGraphId;
  final List<String> tagIds;

  /// Members by graph id.
  final List<TagViewPerson> members;
  final Map<GraphNodeId, Offset> fieldPositions;
  final Map<GraphNodeId, GraphNodeId> followers;

  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) async* {
    final centre = Offset(
      request.canvasSize.width / 2,
      request.canvasSize.height / 2,
    );
    final ego = fieldPositions[egoGraphId] ?? centre;
    final ids = request.nodeIds;
    final pure = computeConstellationTagViewLayout(
      ego: (x: ego.dx, y: ego.dy),
      tagIds: tagIds,
      people: [
        for (final p in members)
          if (ids.contains(p.id)) p,
      ],
    ).positions;
    Offset? placed(GraphNodeId id) {
      final p = pure[id];
      return p == null
          ? null
          : ego +
                (Offset(p.x, p.y) - ego) * kConstellationTagViewRingScale;
    }

    final positions = <GraphNodeId, ScenePoint>{};
    for (final id in ids) {
      final own = placed(id);
      final base = fieldPositions[id];
      final leader = followers[id];
      final leaderNow = leader == null ? null : placed(leader);
      final leaderWas = leader == null ? null : fieldPositions[leader];
      final Offset at;
      if (own != null) {
        at = own;
      } else if (base != null && leaderNow != null && leaderWas != null) {
        at = base + (leaderNow - leaderWas);
      } else {
        at = base ?? centre;
      }
      positions[id] = ScenePoint(x: at.dx, y: at.dy);
    }
    yield GraphLayoutFrame(
      ticket: request.ticket,
      sequence: 0,
      positions: positions,
      isTerminal: true,
    );
  }
}
