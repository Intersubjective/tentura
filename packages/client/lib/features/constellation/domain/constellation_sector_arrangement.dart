import 'dart:math' as math;

import 'layout/layout_geometry.dart';

/// Sector width a new arrangement starts with (#644).
const double kConstellationSectorDefaultSpan = math.pi / 2;

/// Narrowest and widest sector the user can choose.
const double kConstellationSectorMinSpan = math.pi / 6;
const double kConstellationSectorMaxSpan = 2 * math.pi;

/// A person to arrange and where they are drawn now, in scene coordinates.
typedef ConstellationSectorMember = ({String id, LPoint position});

/// Where each person goes, and the arc they span: from `start` (radians)
/// clockwise on screen through `sweep`.
typedef ConstellationSectorLayout = ({
  Map<String, LPoint> targets,
  double start,
  double sweep,
});

/// The direction from [centre] to the middle of [points], in radians (scene
/// coordinates, y down; 0 points right). Each point counts by direction only,
/// so a far person does not outweigh a near one. [fallback] when the points
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

/// Places [members] evenly along an arc around [centre] (#644).
///
/// The arc is centred on [direction] and [span] wide. Each person keeps the
/// distance from [centre] they have now (their distance band) and only moves
/// along it; one closer than [minRadius] is moved out to [minRadius]. People
/// keep their current order around the centre, so nobody crosses over.
///
/// Neighbours sit at least [minSpacing] apart on the closest person's
/// circle: a sector too narrow for that many people is widened, up to the
/// whole circle. When even the whole circle is too small, people are spread
/// evenly around it and may touch.
///
/// A person further out than [maxRadius] is brought in to it, so every
/// target stays inside the stored-position envelope whatever the direction
/// and the spacing stays even.
ConstellationSectorLayout arrangeConstellationSector({
  required LPoint centre,
  required List<ConstellationSectorMember> members,
  required double direction,
  required double span,
  required double minSpacing,
  double minRadius = 0,
  double maxRadius = double.infinity,
}) {
  if (members.isEmpty) {
    return (targets: const {}, start: direction, sweep: 0);
  }
  // Current order around the centre, measured from the opposite side of the
  // arc so the ones already on it keep their side.
  final placed =
      [
        for (final member in members)
          (
            id: member.id,
            radius: math.min(
              maxRadius,
              math.max(minRadius, _distance(member.position, centre)),
            ),
            offset: _angleFrom(direction, member.position, centre),
          ),
      ]..sort((a, b) {
        final byAngle = a.offset.compareTo(b.offset);
        if (byAngle != 0) return byAngle;
        final byRadius = a.radius.compareTo(b.radius);
        return byRadius != 0 ? byRadius : a.id.compareTo(b.id);
      });
  final count = placed.length;
  final step = constellationSectorStep(
    count: count,
    span: span,
    minSpacing: minSpacing,
    nearestRadius: placed.map((p) => p.radius).reduce(math.min),
  );
  final start = direction - step * (count - 1) / 2;
  final result = <String, LPoint>{};
  for (var i = 0; i < count; i++) {
    final angle = start + step * i;
    final radius = placed[i].radius;
    result[placed[i].id] = (
      x: centre.x + math.cos(angle) * radius,
      y: centre.y + math.sin(angle) * radius,
    );
  }
  return (targets: result, start: start, sweep: step * (count - 1));
}

/// The angle between neighbours for [count] people in a [span]-wide sector,
/// widened so neighbours on a circle of [nearestRadius] are [minSpacing]
/// apart, and never more than an even split of the whole circle.
double constellationSectorStep({
  required int count,
  required double span,
  required double minSpacing,
  required double nearestRadius,
}) {
  if (count < 2) return 0;
  final fullCircle = 2 * math.pi / count;
  final chosen = math.min(
    span.clamp(0, kConstellationSectorMaxSpan) / (count - 1),
    fullCircle,
  );
  final needed = nearestRadius <= 0 || minSpacing >= 2 * nearestRadius
      ? fullCircle
      : 2 * math.asin(minSpacing / (2 * nearestRadius));
  return math.min(math.max(chosen, needed), fullCircle);
}

double _distance(LPoint a, LPoint b) {
  final dx = a.x - b.x;
  final dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}

/// Signed angle of [point] around [centre] relative to [direction], in
/// (-π, π].
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
