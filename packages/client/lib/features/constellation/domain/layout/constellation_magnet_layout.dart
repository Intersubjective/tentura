import 'dart:math' as math;

import '../constellation_drag_cluster.dart';
import '../constellation_layout.dart';
import 'layout_geometry.dart';

ConstellationSize _lSizeToConstellation(LSize s) => (width: s.w, height: s.h);

/// A soft layout bias, not a pin: multiple matching magnets contribute equally.
LPoint attractToTagMagnets(LPoint origin, Iterable<LPoint> magnets) {
  var x = 0.0;
  var y = 0.0;
  var count = 0;
  for (final magnet in magnets) {
    x += magnet.x;
    y += magnet.y;
    count++;
  }
  if (count == 0) return origin;
  const strength = 0.8;
  return (
    x: origin.x + (x / count - origin.x) * strength,
    y: origin.y + (y / count - origin.y) * strength,
  );
}

double _halfExtent(LSize size) => math.max(size.w, size.h) / 2;

LRect _nodeRectAt(LPoint centre, LSize size) {
  final h = _halfExtent(size);
  return (left: centre.x - h, top: centre.y - h, right: centre.x + h, bottom: centre.y + h);
}

bool _rectsOverlap(LRect a, LRect b) =>
    a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom;

/// Members of [ownTagIds] that have other Field people in the same tag
/// (excluding ego), for tag-area seating eligibility.
Set<String> constellationTagIdsWithOtherMembersOnField({
  required Set<String> ownTagIds,
  required Set<String> Function(String tagId) peopleOfTag,
  required Set<String> fieldPersonIds,
  required String egoId,
}) {
  if (ownTagIds.isEmpty) return const {};
  final out = <String>{};
  for (final tagId in ownTagIds) {
    final members = peopleOfTag(tagId);
    var other = false;
    for (final id in members) {
      if (id == egoId) continue;
      if (fieldPersonIds.contains(id)) {
        other = true;
        break;
      }
    }
    if (other) {
      out.add(tagId);
    }
  }
  return out;
}

/// Centroid of member centres for [tagId], or null if none have positions.
LPoint? constellationTagMemberCentroidScene({
  required String tagId,
  required Set<String> Function(String tagId) peopleOfTag,
  required Map<String, LPoint> personCentreById,
  required String egoId,
  Set<String> excludePersonIds = const {},
}) {
  var sx = 0.0;
  var sy = 0.0;
  var n = 0;
  for (final id in peopleOfTag(tagId)) {
    if (id == egoId) continue;
    if (excludePersonIds.contains(id)) continue;
    final p = personCentreById[id];
    if (p == null) continue;
    sx += p.x;
    sy += p.y;
    n++;
  }
  if (n == 0) return null;
  return (x: sx / n, y: sy / n);
}

/// Convex hull of member centres (Andrew's monotone chain).
///
/// Returns vertices in counter-clockwise order without duplicate closing point.
/// For one or two points, returns those points in a stable order.
List<LPoint> constellationConvexHullMonotoneChain(Iterable<LPoint> points) {
  final pts = points.toList();
  if (pts.isEmpty) return const [];
  if (pts.length == 1) return [pts.single];
  if (pts.length == 2) {
    final a = pts[0];
    final b = pts[1];
    return a.x < b.x || (a.x == b.x && a.y <= b.y) ? [a, b] : [b, a];
  }
  pts.sort((a, b) {
    final c = a.x.compareTo(b.x);
    return c != 0 ? c : a.y.compareTo(b.y);
  });
  final lower = <LPoint>[];
  for (final p in pts) {
    while (lower.length >= 2 &&
        _cross(lower[lower.length - 2], lower[lower.length - 1], p) <= 0) {
      lower.removeLast();
    }
    lower.add(p);
  }
  final upper = <LPoint>[];
  for (var i = pts.length - 1; i >= 0; i--) {
    final p = pts[i];
    while (upper.length >= 2 &&
        _cross(upper[upper.length - 2], upper[upper.length - 1], p) <= 0) {
      upper.removeLast();
    }
    upper.add(p);
  }
  lower.removeLast();
  upper.removeLast();
  return [...lower, ...upper];
}

double _cross(LPoint o, LPoint a, LPoint b) =>
    (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);

LPoint _closestPointOnSegment(LPoint p, LPoint a, LPoint b) {
  final abx = b.x - a.x;
  final aby = b.y - a.y;
  final apx = p.x - a.x;
  final apy = p.y - a.y;
  final abLen2 = abx * abx + aby * aby;
  if (abLen2 < 1e-18) return a;
  var t = (apx * abx + apy * aby) / abLen2;
  t = t.clamp(0.0, 1.0);
  return (x: a.x + t * abx, y: a.y + t * aby);
}

LPoint _closestPointOnClosedPolygonBoundary(LPoint p, List<LPoint> hull) {
  if (hull.isEmpty) return p;
  if (hull.length == 1) return hull[0];
  if (hull.length == 2) {
    return _closestPointOnSegment(p, hull[0], hull[1]);
  }
  var best = hull[0];
  var bestD = _dist2(p, best);
  for (var i = 0; i < hull.length; i++) {
    final a = hull[i];
    final b = hull[(i + 1) % hull.length];
    final q = _closestPointOnSegment(p, a, b);
    final d = _dist2(p, q);
    if (d < bestD) {
      bestD = d;
      best = q;
    }
  }
  return best;
}

double _pointSegmentDistanceSquared(LPoint p, LPoint a, LPoint b) {
  final abx = b.x - a.x;
  final aby = b.y - a.y;
  final apx = p.x - a.x;
  final apy = p.y - a.y;
  final abLen2 = abx * abx + aby * aby;
  if (abLen2 < 1e-18) {
    final dx = p.x - a.x;
    final dy = p.y - a.y;
    return dx * dx + dy * dy;
  }
  var t = (apx * abx + apy * aby) / abLen2;
  t = t.clamp(0.0, 1.0);
  final cx = a.x + t * abx;
  final cy = a.y + t * aby;
  final dx = p.x - cx;
  final dy = p.y - cy;
  return dx * dx + dy * dy;
}

/// Whether [point] lies inside [hull] or on its boundary. [hull] is CCW for ≥ 3.
bool constellationPointInOrOnConvexHull(LPoint point, List<LPoint> hull) {
  if (hull.length == 1) {
    return _dist2(point, hull[0]) < 0.25;
  }
  if (hull.length == 2) {
    return _pointSegmentDistanceSquared(point, hull[0], hull[1]) < 0.25;
  }
  if (hull.length < 3) return false;
  for (var i = 0; i < hull.length; i++) {
    final a = hull[i];
    final b = hull[(i + 1) % hull.length];
    if (_cross(a, b, point) < -1e-9) {
      return false;
    }
  }
  return true;
}

/// Squared distance from [point] to the boundary of [hull]. Zero if inside.
double constellationSquaredDistanceToHullBoundary(LPoint point, List<LPoint> hull) {
  if (hull.isEmpty) {
    return double.infinity;
  }
  if (hull.length == 1) {
    final dx = point.x - hull[0].x;
    final dy = point.y - hull[0].y;
    return dx * dx + dy * dy;
  }
  if (hull.length == 2) {
    return _pointSegmentDistanceSquared(point, hull[0], hull[1]);
  }
  if (constellationPointInOrOnConvexHull(point, hull)) {
    return 0;
  }
  var best = double.infinity;
  for (var i = 0; i < hull.length; i++) {
    final a = hull[i];
    final b = hull[(i + 1) % hull.length];
    final d = _pointSegmentDistanceSquared(point, a, b);
    if (d < best) best = d;
  }
  return best;
}

/// Target for tag-area seating: single-tag centroid, multi-tag average of
/// per-tag centroids, clamped to drag bounds. [tagMagnetsScene] wins when set.
LPoint? constellationTagAreaSeatingTargetScene({
  required Set<String> eligibleTagIds,
  required Map<String, LPoint?> tagCentroidScene,
  required Map<String, LPoint> tagMagnetsScene,
  required LSize movingSize,
}) {
  if (eligibleTagIds.isEmpty) return null;
  final sorted = eligibleTagIds.toList()..sort();
  final centres = <LPoint>[];
  for (final tagId in sorted) {
    final magnet = tagMagnetsScene[tagId];
    if (magnet != null) {
      centres.add(magnet);
      continue;
    }
    final c = tagCentroidScene[tagId];
    if (c != null) {
      centres.add(c);
    }
  }
  if (centres.isEmpty) return null;
  LPoint combined;
  if (centres.length == 1) {
    combined = centres.single;
  } else {
    var sx = 0.0;
    var sy = 0.0;
    for (final c in centres) {
      sx += c.x;
      sy += c.y;
    }
    combined = (x: sx / centres.length, y: sy / centres.length);
  }
  return constellationClampToDragBounds(combined, size: _lSizeToConstellation(movingSize));
}

LPoint _spiralJiggleToward({
  required LPoint from,
  required LPoint toward,
  required LSize movingSize,
  required Iterable<LRect> obstacleRects,
  required LRect Function(LPoint centre) rectForCentre,
  int maxSteps = 64,
}) {
  final obstacleList = [...obstacleRects];
  var centre = from;
  for (var step = 0; step < maxSteps; step++) {
    final rect = rectForCentre(centre);
    var hit = false;
    for (final o in obstacleList) {
      if (_rectsOverlap(rect, o)) {
        hit = true;
        break;
      }
    }
    if (!hit) {
      return centre;
    }
    final t = (step + 1) / maxSteps;
    final angle = t * 12 * math.pi;
    final radius = 6.0 * (step + 1);
    final dx = toward.x - from.x;
    final dy = toward.y - from.y;
    final d = math.sqrt(dx * dx + dy * dy);
    final ux = d < 1e-9 ? 0.0 : dx / d;
    final uy = d < 1e-9 ? 0.0 : dy / d;
    final jx = math.cos(angle) * radius;
    final jy = math.sin(angle) * radius;
    centre = (
      x: from.x + ux * (radius * 0.5) + jx * 0.3,
      y: from.y + uy * (radius * 0.5) + jy * 0.3,
    );
    final clamped = constellationClampToDragBounds(centre, size: _lSizeToConstellation(movingSize));
    centre = (x: clamped.x, y: clamped.y);
  }
  return constellationClampToDragBounds(from, size: _lSizeToConstellation(movingSize));
}

/// Moves [movingCentre] to a non-overlapping point near [target], staying inside
/// tag hull(s) when [insideHull] is non-null, else within [maxRadius] of [target].
LPoint constellationTagAreaSeatingResolvePositionScene({
  required LPoint movingCentre,
  required LPoint target,
  required LSize movingSize,
  required Iterable<LRect> obstacles,
  required List<LPoint>? insideHull,
  required double maxRadius,
}) {
  LRect rectAt(LPoint c) => _nodeRectAt(c, movingSize);

  bool overlaps(LPoint c) {
    final r = rectAt(c);
    for (final o in obstacles) {
      if (_rectsOverlap(r, o)) {
        return true;
      }
    }
    return false;
  }

  LPoint clampHull(LPoint c) {
    var p = c;
    final h = insideHull;
    if (h != null && h.isNotEmpty) {
      if (!constellationPointInOrOnConvexHull(p, h)) {
        p = _closestPointOnClosedPolygonBoundary(p, h);
      }
    }
    return constellationClampToDragBounds(p, size: _lSizeToConstellation(movingSize));
  }

  final candidate = clampHull(
    constellationClampToDragBounds(target, size: _lSizeToConstellation(movingSize)),
  );
  if (!overlaps(candidate) &&
      _withinRadius(candidate, target, maxRadius) &&
      (insideHull == null ||
          insideHull.length < 2 ||
          constellationPointInOrOnConvexHull(candidate, insideHull))) {
    return candidate;
  }

  const step = 9.0;
  const rings = 36;
  for (var ring = 1; ring <= rings; ring++) {
    final r = ring * step;
    if (r > maxRadius + step) break;
    for (var i = 0; i < 24; i++) {
      final ang = (i / 24) * 2 * math.pi + ring * 0.17;
      final tryCentre = (
        x: target.x + r * math.cos(ang),
        y: target.y + r * math.sin(ang),
      );
      final c = clampHull(tryCentre);
      if (!overlaps(c) &&
          _withinRadius(c, target, maxRadius) &&
          (insideHull == null ||
              insideHull.length < 2 ||
              constellationPointInOrOnConvexHull(c, insideHull))) {
        return c;
      }
    }
  }

  return _spiralJiggleToward(
    from: movingCentre,
    toward: target,
    movingSize: movingSize,
    obstacleRects: obstacles,
    rectForCentre: rectAt,
  );
}

double _dist2(LPoint a, LPoint b) {
  final dx = a.x - b.x;
  final dy = a.y - b.y;
  return dx * dx + dy * dy;
}

bool _withinRadius(LPoint p, LPoint target, double maxR) =>
    _dist2(p, target) <= maxR * maxR + 1e-6;

/// Radius around a tag centre matching «Rearrange everyone» disk scale (#1020).
double constellationTagAreaRadiusForSeating({
  required int memberCount,
  required double maxCell,
}) {
  final n = math.max(1, memberCount);
  final cell = math.max(maxCell, 1e-6);
  return 2.5 * math.sqrt(n.toDouble()) * cell;
}
