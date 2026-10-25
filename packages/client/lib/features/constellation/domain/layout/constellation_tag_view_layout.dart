import 'dart:math' as math;

import '../constellation_consts.dart';
import 'layout_geometry.dart';

/// Largest tag that keeps each person's Field direction; bigger tags fall back
/// to one ring per trust depth.
const kConstellationTagViewDirectionalMax = 30;

/// One member of the tag view: Field angle from ego, trust depth, and the tags
/// (of the viewed set) the person belongs to.
typedef TagViewPerson = ({
  String id,
  double angle,
  int depth,
  Set<String> tagIds,
});

/// Tag view positions plus the centre each tag's cluster was built around.
typedef TagViewLayout = ({
  Map<String, LPoint> positions,
  Map<String, LPoint> clusterCentres,
});

LPoint _polar(LPoint ego, double angle, double radius) => (
  x: ego.x + radius * math.cos(angle),
  y: ego.y + radius * math.sin(angle),
);

/// Pure, deterministic tag view layout around [ego]; writes no anchors.
///
/// Up to [kConstellationTagViewDirectionalMax] people keep their Field
/// direction with radial gaps between occupied depths closed; more people sit
/// on one ring per trust depth. With several [tagIds] each tag gets a cluster
/// centre (mean direction and radius of its members) and a person in several
/// tags is placed midway between those centres.
TagViewLayout computeConstellationTagViewLayout({
  required LPoint ego,
  required List<String> tagIds,
  required List<TagViewPerson> people,
}) {
  final sorted = [...people]..sort((a, b) => a.id.compareTo(b.id));
  final depths = {for (final p in sorted) p.depth}.toList()..sort();
  double ringRadius(int depth) =>
      (depths.indexOf(depth) + 1) * kConstellationRingUnitPixels;

  final positions = <String, LPoint>{};
  final centres = <String, LPoint>{};

  if (sorted.length > kConstellationTagViewDirectionalMax) {
    for (final depth in depths) {
      final ring = sorted.where((p) => p.depth == depth).toList()
        ..sort((a, b) {
          final byAngle = a.angle.compareTo(b.angle);
          return byAngle != 0 ? byAngle : a.id.compareTo(b.id);
        });
      for (var i = 0; i < ring.length; i++) {
        positions[ring[i].id] = _polar(
          ego,
          -math.pi + i * 2 * math.pi / ring.length,
          ringRadius(depth),
        );
      }
    }
    return (positions: positions, clusterCentres: centres);
  }

  final own = {
    for (final p in sorted) p.id: _polar(ego, p.angle, ringRadius(p.depth)),
  };

  for (final tagId in tagIds) {
    final members = sorted.where((p) => p.tagIds.contains(tagId)).toList();
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

  for (final p in sorted) {
    final memberCentres = [
      for (final t in tagIds)
        if (p.tagIds.contains(t) && centres[t] != null) centres[t]!,
    ];
    if (memberCentres.length < 2) {
      positions[p.id] = own[p.id]!;
    } else {
      positions[p.id] = (
        x: memberCentres.map((c) => c.x).reduce((a, b) => a + b) /
            memberCentres.length,
        y: memberCentres.map((c) => c.y).reduce((a, b) => a + b) /
            memberCentres.length,
      );
    }
  }
  return (positions: positions, clusterCentres: centres);
}
