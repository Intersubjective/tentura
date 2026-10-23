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
/// `start` (radians) clockwise on screen through `sweep`, from `inner` out to
/// `outer`.
typedef ConstellationSectorLayout = ({
  Map<String, LPoint> targets,

  /// Radius of every ring that holds a node, innermost first.
  List<double> rings,
  double start,
  double sweep,

  /// The radii the sector spans: exactly the ones asked for (the outer one
  /// never less than the inner one).
  double inner,
  double outer,

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

/// The outer radius «Arrange in a sector» starts with (#644): the last ring
/// when [count] nodes fill rings [minSpacing] apart from [innerRadius] (never
/// less than [minSpacing]) outward, each ring taking as many as fit with
/// neighbours [minSpacing] apart. So a new sector is as compact as it can be
/// without overlaps; the user may then make it wider or tighter.
double constellationSectorCompactOuterRadius({
  required double innerRadius,
  required double span,
  required int count,
  required double minSpacing,
}) {
  final spacing = math.max(minSpacing, 1e-6);
  final sweep = span.clamp(
    kConstellationSectorMinSpan,
    kConstellationSectorMaxSpan,
  );
  var radius = math.max(innerRadius, spacing);
  var left = count;
  while (true) {
    left -= constellationSectorRingCapacity(
      radius: radius,
      span: sweep,
      minSpacing: spacing,
    );
    if (left <= 0) return radius;
    radius += spacing;
  }
}

/// Places [members] evenly in the ring band of a sector around [centre]
/// (#644).
///
/// The sector is centred on [direction] and [span] wide (a full circle at
/// [kConstellationSectorMaxSpan]) and reaches from [innerRadius] out to
/// [outerRadius] (never less than [innerRadius]). Both radii are kept
/// exactly, however tight: when the band is too small for the nodes they end
/// up closer together, even overlapping, and the user judges by eye.
///
/// Rings: one ring sits half way between the radii (on the inner one when
/// they are equal); two or more go from the inner radius to the outer one at
/// equal steps. Each ring takes a share of the nodes in proportion to its
/// length, at least one, so the steps along every ring are about the same.
/// Of the ring counts possible (one up to one per node) the one that keeps
/// the nearest neighbours furthest apart wins — along a ring or from ring to
/// ring — which makes each node's cell about as deep as it is wide. Ties go
/// to fewer rings.
///
/// [minSpacing] (the room a node takes) only steers that choice: where rings
/// are at least [minSpacing] apart and can hold every node with neighbours
/// [minSpacing] apart ([constellationSectorRingCapacity]), no ring takes
/// more than that, so a band with room for the nodes never overlaps them.
///
/// Each ring divides the whole sector into as many equal cells as it holds
/// nodes and puts one in the middle of each: the spacing along a ring is
/// even, every ring is spread over the whole sector, every target is
/// strictly inside the sector, and a full circle has no doubled place at its
/// seam.
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
  required double outerRadius,
  required double minSpacing,
  LRect? bounds,
}) {
  final sweep = span.clamp(
    kConstellationSectorMinSpan,
    kConstellationSectorMaxSpan,
  );
  final start = direction - sweep / 2;
  final inner = innerRadius < 0 ? 0.0 : innerRadius;
  final outer = math.max(outerRadius, inner);
  if (members.isEmpty) {
    return (
      targets: const {},
      rings: const [],
      start: start,
      sweep: sweep,
      inner: inner,
      outer: outer,
      outside: const {},
    );
  }
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
  final plan = _bestRings(
    count: ranked.length,
    inner: inner,
    outer: outer,
    sweep: sweep,
    minSpacing: minSpacing,
  );
  final targets = <String, LPoint>{};
  var next = 0;
  for (var ring = 0; ring < plan.rings.length; ring++) {
    final radius = plan.rings[ring];
    final count = plan.counts[ring];
    final onRing = ranked.sublist(next, next + count)
      ..sort((a, b) {
        final byAngle = a.offset.compareTo(b.offset);
        if (byAngle != 0) return byAngle;
        final byDistance = a.distance.compareTo(b.distance);
        return byDistance != 0 ? byDistance : a.id.compareTo(b.id);
      });
    next += count;
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
    rings: plan.rings,
    start: start,
    sweep: sweep,
    inner: inner,
    outer: outer,
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

/// The radii of [rings] rings in the band from [inner] to [outer]: half way
/// for one, equal steps from edge to edge for more.
List<double> constellationSectorRingRadii({
  required int rings,
  required double inner,
  required double outer,
}) => [
  if (rings <= 1)
    (inner + outer) / 2
  else ...[
    for (var i = 0; i < rings - 1; i++)
      inner + (outer - inner) * i / (rings - 1),
    outer,
  ],
];

/// How many of [count] nodes each ring of [radii] takes: in proportion to
/// its length, at least one each and at most its [caps] (largest remainders
/// get the rest; ties go to the inner ring). The caps must hold [count], and
/// there must be no more rings than nodes.
List<int> _shares(int count, List<double> radii, List<int>? caps) {
  final total = radii.fold<double>(0, (sum, r) => sum + r);
  final ideal = [
    for (final radius in radii)
      if (total <= 0) count / radii.length else count * radius / total,
  ];
  final shares = [
    for (var i = 0; i < radii.length; i++)
      math.max(1, math.min(ideal[i].floor(), caps?[i] ?? count)),
  ];
  var sum = shares.fold<int>(0, (a, b) => a + b);
  while (sum < count) {
    int? pick;
    for (var i = 0; i < shares.length; i++) {
      if (caps != null && shares[i] >= caps[i]) continue;
      if (pick == null ||
          ideal[i] - shares[i] > ideal[pick] - shares[pick] + 1e-12) {
        pick = i;
      }
    }
    shares[pick!]++;
    sum++;
  }
  while (sum > count) {
    int? pick;
    for (var i = shares.length - 1; i >= 0; i--) {
      if (shares[i] <= 1) continue;
      if (pick == null ||
          ideal[i] - shares[i] < ideal[pick] - shares[pick] - 1e-12) {
        pick = i;
      }
    }
    shares[pick!]--;
    sum--;
  }
  return shares;
}

/// The rings and shares that keep the nearest neighbours furthest apart.
({List<double> rings, List<int> counts}) _bestRings({
  required int count,
  required double inner,
  required double outer,
  required double sweep,
  required double minSpacing,
}) {
  ({List<double> rings, List<int> counts})? best;
  var bestGap = -1.0;
  for (var k = 1; k <= count; k++) {
    final radii = constellationSectorRingRadii(
      rings: k,
      inner: inner,
      outer: outer,
    );
    final step = k == 1 ? double.infinity : (outer - inner) / (k - 1);
    // Room for every node a spacing apart: keep to it.
    List<int>? caps;
    if (minSpacing > 0 && step >= minSpacing * (1 - 1e-9)) {
      final room = [
        for (final radius in radii)
          constellationSectorRingCapacity(
            radius: radius,
            span: sweep,
            minSpacing: minSpacing,
          ),
      ];
      if (room.fold<int>(0, (a, b) => a + b) >= count) caps = room;
    }
    final shares = _shares(count, radii, caps);
    // Ring to ring, and along each ring (the chord between neighbours, the
    // seam of a full circle included; a lone node has no neighbour there).
    var gap = step;
    for (var i = 0; i < k; i++) {
      if (shares[i] < 2) continue;
      gap = math.min(gap, 2 * radii[i] * math.sin(sweep / (2 * shares[i])));
    }
    if (!gap.isFinite) gap = sweep * radii.first;
    if (best == null || gap > bestGap * (1 + 1e-9) + 1e-9) {
      best = (rings: radii, counts: shares);
      bestGap = gap;
    }
    // More rings only bring them closer together from here on.
    if (k > 1 && step < bestGap) break;
  }
  return best!;
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
