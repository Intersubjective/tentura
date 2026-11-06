import 'dart:math' as math;

import 'layout_geometry.dart';

/// One member of the tag view: Field angle from ego, trust depth, and the tags
/// (of the viewed set) the person belongs to.
typedef TagViewPerson = ({
  String id,
  double angle,
  int depth,
  Set<String> tagIds,
});

LPoint _polar(LPoint ego, double angle, double radius) => (
  x: ego.x + radius * math.cos(angle),
  y: ego.y + radius * math.sin(angle),
);

/// Cluster centres and member positions for tag-view-style grouping.
///
/// The `sortedPeople` list must be sorted by id. Each tag's centre is the mean
/// direction (vector average of member Field angles) and mean radial distance
/// from ego (average of the `ringRadius` callback at each member's trust
/// depth). A person
/// in one tag keeps their Field direction and depth; a person in several tags
/// is placed at the arithmetic mean of those tags' cluster centres.
typedef TagViewClusterLayout = ({
  Map<String, LPoint> clusterCentres,
  Map<String, LPoint> positions,
});

TagViewClusterLayout computeConstellationTagViewClusterLayout({
  required LPoint ego,
  required List<String> tagIds,
  required List<TagViewPerson> sortedPeople,
  required double Function(int depth) ringRadius,
}) {
  final own = {
    for (final p in sortedPeople)
      p.id: _polar(ego, p.angle, ringRadius(p.depth)),
  };

  final centres = <String, LPoint>{};
  for (final tagId in tagIds) {
    final members = sortedPeople
        .where((p) => p.tagIds.contains(tagId))
        .toList();
    if (members.isEmpty) continue;
    var sx = 0.0;
    var sy = 0.0;
    var radius = 0.0;
    for (final p in members) {
      sx += math.cos(p.angle);
      sy += math.sin(p.angle);
      radius += ringRadius(p.depth);
    }
    final angle = (sx.abs() < 1e-9 && sy.abs() < 1e-9)
        ? 0.0
        : math.atan2(sy, sx);
    centres[tagId] = _polar(ego, angle, radius / members.length);
  }

  final positions = <String, LPoint>{};
  for (final p in sortedPeople) {
    final memberCentres = [
      for (final t in tagIds)
        if (p.tagIds.contains(t) && centres[t] != null) centres[t]!,
    ];
    if (memberCentres.length < 2) {
      positions[p.id] = own[p.id]!;
    } else {
      positions[p.id] = (
        x:
            memberCentres.map((c) => c.x).reduce((a, b) => a + b) /
            memberCentres.length,
        y:
            memberCentres.map((c) => c.y).reduce((a, b) => a + b) /
            memberCentres.length,
      );
    }
  }

  return (clusterCentres: centres, positions: positions);
}
