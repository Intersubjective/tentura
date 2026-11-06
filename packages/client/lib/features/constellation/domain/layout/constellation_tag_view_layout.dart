import 'dart:math' as math;

import '../constellation_consts.dart';
import 'constellation_tag_view_cluster_layout.dart';
import 'layout_geometry.dart';

export 'constellation_tag_view_cluster_layout.dart'
    show TagViewPerson, computeConstellationTagViewClusterLayout;

/// Largest tag that keeps each person's Field direction; bigger tags fall back
/// to one ring per trust depth.
const kConstellationTagViewDirectionalMax = 30;

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

  final cluster = computeConstellationTagViewClusterLayout(
    ego: ego,
    tagIds: tagIds,
    sortedPeople: sorted,
    ringRadius: ringRadius,
  );
  positions.addAll(cluster.positions);
  centres.addAll(cluster.clusterCentres);
  return (positions: positions, clusterCentres: centres);
}
