import 'dart:math' as math;

import 'layout/layout_geometry.dart';

/// Sector width a new arrangement starts with (#644).
const double kConstellationSectorDefaultSpan = math.pi / 2;

/// Narrowest and widest sector the user can choose.
const double kConstellationSectorMinSpan = math.pi / 12;
const double kConstellationSectorMaxSpan = 2 * math.pi;

/// A node to arrange (a person, a Request or a Post) and where it is drawn
/// now, in scene coordinates.
typedef ConstellationSectorMember = ({String id, LPoint position});

/// Where each node goes, the rings it fills and the sector they fill: from
/// `start` (radians) clockwise on screen through `sweep`.
typedef ConstellationSectorLayout = ({
  Map<String, LPoint> targets,

  /// Radius of every ring that holds a node, innermost first.
  List<double> rings,
  double start,
  double sweep,

  /// The nodes whose target falls outside the bounds asked for.
  Set<String> outside,
});

/// The direction from [centre] to the middle of [points], in radians (scene
/// coordinates, y down; 0 points right). Each point counts by direction only,
/// so a far node does not outweigh a near one. [fallback] when the points
/// cancel out or there are none.
double constellationSectorCentroidDirection({
  required LPoint centre,
  required Iterable<LPoint> points,
  double fallback = -math.pi / 2,
}) {
  var x = 0.0;
  var y = 0.0;
  for (final point in points) {
    final dx = point.x - centre.x;
    final dy = point.y - centre.y;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length < 1e-9) continue;
    x += dx / length;
    y += dy / length;
  }
  if (math.sqrt(x * x + y * y) < 1e-6) return fallback;
  return math.atan2(y, x);
}

/// How many nodes fit on a ring of [radius] across a [span]-wide sector
/// with neighbours (straight line, so the seam of a full circle included)
/// at least [minSpacing] apart. Always at least one: a lone node needs no
/// neighbour room.
int constellationSectorRingCapacity({
  required double radius,
  required double span,
  required double minSpacing,
}) {
  if (radius <= 0 || minSpacing > 2 * radius) return 1;
  final step = 2 * math.asin(minSpacing / (2 * radius));
  // The tolerance keeps a ring that fits exactly from losing a place to
  // rounding.
  return math.max(
    1,
    (span.clamp(0, kConstellationSectorMaxSpan) / step + 1e-9).floor(),
  );
}

/// Places [members] evenly in rings inside a sector around [centre] (#644).
///
/// The sector is centred on [direction] and [span] wide (a full circle at
/// [kConstellationSectorMaxSpan]). The first ring has [innerRadius], never
/// less than [minSpacing] so nothing lands on what sits at the centre; each
/// further ring is [minSpacing] further out. A ring takes as many nodes as
/// fit with neighbours [minSpacing] apart
/// ([constellationSectorRingCapacity]); inner rings fill first, and rings
/// are added outward until every node has a place, so no two targets are
/// ever closer than [minSpacing].
///
/// Each ring divides the whole sector into as many equal cells as it holds
/// nodes and puts one in the middle of each: the spacing along a ring is
/// even, the outermost ring is spread over the whole sector rather than
/// bunched at one edge, every target is strictly inside the sector, and a
/// full circle has no doubled place at its seam.
///
/// Order (who goes where): nodes are ranked by their current distance from
/// [centre]; the nearest fill the inner ring, the next ones the next ring.
/// Within a ring they keep their current order around the centre, measured
/// from the side opposite the sector so the ones already in it keep their
/// side. So nodes move as little as possible, nobody on a ring crosses
/// another, and arranging an arrangement again changes nothing. Ties go by
/// angle, then id, so the result is deterministic.
///
/// With [bounds], the nodes whose target falls outside them are listed in
/// `outside`; the layout itself is not changed.
ConstellationSectorLayout arrangeConstellationSector({
  required LPoint centre,
  required List<ConstellationSectorMember> members,
  required double direction,
  required double span,
  required double innerRadius,
  required double minSpacing,
  LRect? bounds,
}) {
  final sweep = span.clamp(
    kConstellationSectorMinSpan,
    kConstellationSectorMaxSpan,
  );
  final start = direction - sweep / 2;
  if (members.isEmpty) {
    return (
      targets: const {},
      rings: const [],
      start: start,
      sweep: sweep,
      outside: const {},
    );
  }
  final spacing = math.max(minSpacing, 1e-6);
  final firstRadius = math.max(innerRadius, spacing);
  final ranked =
      [
        for (final member in members)
          (
            id: member.id,
            distance: _distance(member.position, centre),
            offset: _angleFrom(direction, member.position, centre),
          ),
      ]..sort((a, b) {
        final byDistance = a.distance.compareTo(b.distance);
        if (byDistance != 0) return byDistance;
        final byAngle = a.offset.compareTo(b.offset);
        return byAngle != 0 ? byAngle : a.id.compareTo(b.id);
      });
  final targets = <String, LPoint>{};
  final rings = <double>[];
  var next = 0;
  for (var ring = 0; next < ranked.length; ring++) {
    final radius = firstRadius + ring * spacing;
    final capacity = constellationSectorRingCapacity(
      radius: radius,
      span: sweep,
      minSpacing: spacing,
    );
    final count = math.min(capacity, ranked.length - next);
    final onRing = ranked.sublist(next, next + count)
      ..sort((a, b) {
        final byAngle = a.offset.compareTo(b.offset);
        if (byAngle != 0) return byAngle;
        final byDistance = a.distance.compareTo(b.distance);
        return byDistance != 0 ? byDistance : a.id.compareTo(b.id);
      });
    next += count;
    rings.add(radius);
    final cell = sweep / count;
    for (var i = 0; i < count; i++) {
      final angle = start + cell * (i + 0.5);
      targets[onRing[i].id] = (
        x: centre.x + math.cos(angle) * radius,
        y: centre.y + math.sin(angle) * radius,
      );
    }
  }
  return (
    targets: targets,
    rings: rings,
    start: start,
    sweep: sweep,
    outside: bounds == null
        ? const {}
        : {
            for (final MapEntry(key: id, value: point) in targets.entries)
              if (point.x < bounds.left ||
                  point.x > bounds.right ||
                  point.y < bounds.top ||
                  point.y > bounds.bottom)
                id,
          },
  );
}

double _distance(LPoint a, LPoint b) {
  final dx = a.x - b.x;
  final dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}

/// Signed angle of [point] around [centre] relative to [direction], in
/// (-π, π]; 0 for a point on the centre.
double _angleFrom(double direction, LPoint point, LPoint centre) {
  final dx = point.x - centre.x;
  final dy = point.y - centre.y;
  if (dx.abs() < 1e-9 && dy.abs() < 1e-9) return 0;
  var delta = math.atan2(dy, dx) - direction;
  while (delta <= -math.pi) {
    delta += 2 * math.pi;
  }
  while (delta > math.pi) {
    delta -= 2 * math.pi;
  }
  return delta;
}
