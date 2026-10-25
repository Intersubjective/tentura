import 'dart:math' as math;

import 'layout/layout_geometry.dart';

/// A node to gather and where it is drawn now, in scene coordinates.
typedef ConstellationGatherMember = ({String id, LPoint position});

/// «Gather»: puts [members] in a compact square grid, neighbours [spacing]
/// apart, centred exactly on the centroid of where they are now. Nodes are
/// assigned to places by id, so the result does not depend on the order the
/// selection was picked in. Nothing to gather (an empty map) for fewer than
/// two nodes.
Map<String, LPoint> arrangeConstellationGather({
  required List<ConstellationGatherMember> members,
  required double spacing,
}) {
  if (members.length < 2) return const {};
  // Summed in id order so the centroid is bit-for-bit the same whatever order
  // the selection was picked in.
  final sorted = [...members]..sort((a, b) => a.id.compareTo(b.id));
  final count = sorted.length;
  final centre = (
    x: sorted.fold<double>(0, (sum, m) => sum + m.position.x) / count,
    y: sorted.fold<double>(0, (sum, m) => sum + m.position.y) / count,
  );
  final columns = math.sqrt(count).ceil();
  final cells = [
    for (var i = 0; i < count; i++)
      (x: (i % columns) * spacing, y: (i ~/ columns) * spacing),
  ];
  // An incomplete last row would pull the grid off the centroid: centre the
  // cells on their own mean instead of the grid's middle.
  final meanX = cells.fold<double>(0, (sum, c) => sum + c.x) / count;
  final meanY = cells.fold<double>(0, (sum, c) => sum + c.y) / count;
  final ids = [for (final m in sorted) m.id];
  return {
    for (var i = 0; i < count; i++)
      ids[i]: (
        x: centre.x + cells[i].x - meanX,
        y: centre.y + cells[i].y - meanY,
      ),
  };
}
