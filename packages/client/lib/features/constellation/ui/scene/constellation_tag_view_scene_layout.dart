import 'package:force_directed_graphview/force_directed_graphview.dart';

import '../../domain/layout/constellation_tag_view_layout.dart';

/// [SceneLayoutAlgorithm] wrapper: no pins, one terminal frame, ego at the
/// canvas centre.
class ConstellationTagViewSceneLayoutAlgorithm implements SceneLayoutAlgorithm {
  const ConstellationTagViewSceneLayoutAlgorithm({
    required this.tagIds,
    required this.people,
  });

  final List<String> tagIds;
  final List<TagViewPerson> people;

  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) async* {
    final ids = request.nodeIds;
    final pure = computeConstellationTagViewLayout(
      ego: (x: request.canvasSize.width / 2, y: request.canvasSize.height / 2),
      tagIds: tagIds,
      people: [
        for (final p in people)
          if (ids.contains(p.id)) p,
      ],
    );
    yield GraphLayoutFrame(
      ticket: request.ticket,
      sequence: 0,
      positions: {
        for (final e in pure.positions.entries)
          e.key: ScenePoint(x: e.value.x, y: e.value.y),
      },
      isTerminal: true,
    );
  }
}
