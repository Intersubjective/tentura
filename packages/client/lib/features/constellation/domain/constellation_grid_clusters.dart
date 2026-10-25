import 'layout/layout_geometry.dart';

/// Overview cells use logical screen points, independent of camera scale.
const kConstellationGridCellSize = 72.0;

typedef ConstellationGridCluster = ({
  LPoint centre,
  List<String> personIds,
  String? dominantTagId,
});

/// Groups projected people, never world positions or tag memberships. Tags
/// only name a cell; equal frequencies are resolved by the owner's tag order.
List<ConstellationGridCluster> computeConstellationGridClusters({
  required Map<String, LPoint> screenPositions,
  List<String> ownTagIdsInOrder = const [],
  Map<String, Set<String>> ownTagIdsByPerson = const {},
}) {
  final cells = <(int, int), List<String>>{};
  for (final id in screenPositions.keys.toList()..sort()) {
    final point = screenPositions[id]!;
    final cell = (
      (point.x / kConstellationGridCellSize).floor(),
      (point.y / kConstellationGridCellSize).floor(),
    );
    (cells[cell] ??= []).add(id);
  }
  return [
    for (final entry in cells.entries)
      () {
        String? dominant;
        var most = 0;
        for (final tagId in ownTagIdsInOrder) {
          final count = entry.value
              .where(
                (id) => ownTagIdsByPerson[id]?.contains(tagId) ?? false,
              )
              .length;
          if (count > most) {
            dominant = tagId;
            most = count;
          }
        }
        return (
          centre: (
            x: (entry.key.$1 + 0.5) * kConstellationGridCellSize,
            y: (entry.key.$2 + 0.5) * kConstellationGridCellSize,
          ),
          personIds: List<String>.unmodifiable(entry.value),
          dominantTagId: dominant,
        );
      }(),
  ];
}
