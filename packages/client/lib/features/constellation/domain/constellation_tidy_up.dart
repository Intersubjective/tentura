import 'dart:math' as math;

import 'constellation_nearest_ring.dart';
import 'layout/layout_geometry.dart';

/// One person as «Tidy up» sees them: a circle of `radius` at `position` with
/// a label box of `labelSize` centred under it.
typedef ConstellationTidyNode = ({
  String id,
  LPoint position,
  double radius,
  LSize labelSize,
  bool pinned,
});

/// The new positions of the people «Tidy up» displaced; `movedCount` is how
/// many.
typedef ConstellationTidyResult = ({Map<String, LPoint> moves, int movedCount});

/// Furthest anyone moves, in node diameters.
const double kConstellationTidyMaxMoveDiameters = 1.5;

const _step = 0.5;
const _maxPasses = 4000;

/// Resolves node and label overlaps by sliding people along their own trust
/// ring, so ring and angular order are kept. Pinned people never move; with a
/// [selection] or [visibleRect] only people inside it move, the rest stay as
/// obstacles. Deterministic.
ConstellationTidyResult constellationTidyUp({
  required LPoint ego,
  required List<ConstellationTidyNode> nodes,
  Set<String>? selection,
  LRect? visibleRect,
}) {
  bool movable(ConstellationTidyNode n) =>
      !n.pinned &&
      (selection?.contains(n.id) ?? true) &&
      (visibleRect == null ||
          (n.position.x >= visibleRect.left &&
              n.position.x <= visibleRect.right &&
              n.position.y >= visibleRect.top &&
              n.position.y <= visibleRect.bottom));

  final rings = <int, List<int>>{};
  for (var i = 0; i < nodes.length; i++) {
    rings
        .putIfAbsent(
          constellationNearestRing(centre: ego, point: nodes[i].position).steps,
          () => [],
        )
        .add(i);
  }

  final moves = <String, LPoint>{};
  for (final group in rings.values) {
    if (group.length < 2) continue;
    _tidyRing(ego, nodes, group, movable, moves);
  }
  return (moves: moves, movedCount: moves.length);
}

void _tidyRing(
  LPoint ego,
  List<ConstellationTidyNode> nodes,
  List<int> group,
  bool Function(ConstellationTidyNode) movable,
  Map<String, LPoint> moves,
) {
  final n = group.length;
  final radii = [
    for (final i in group)
      math.sqrt(
        math.pow(nodes[i].position.x - ego.x, 2) +
            math.pow(nodes[i].position.y - ego.y, 2),
      ),
  ];
  final base = [
    for (final i in group)
      math.atan2(nodes[i].position.y - ego.y, nodes[i].position.x - ego.x),
  ];
  final free = [
    for (final i in group) movable(nodes[i]) && radii[group.indexOf(i)] > 1e-6,
  ];
  final shift = List<double>.filled(n, 0); // arc length moved
  final pos = [for (final i in group) nodes[i].position];

  LPoint at(int k) => (
    x: ego.x + math.cos(base[k] + shift[k] / radii[k]) * radii[k],
    y: ego.y + math.sin(base[k] + shift[k] / radii[k]) * radii[k],
  );
  final cap =
      kConstellationTidyMaxMoveDiameters *
      2 *
      group.map((i) => nodes[i].radius).reduce(math.min) *
      0.999;

  for (var pass = 0; pass < _maxPasses; pass++) {
    final push = List<double>.filled(n, 0);
    var conflicts = false;
    for (var a = 0; a < n; a++) {
      for (var b = a + 1; b < n; b++) {
        if (!free[a] && !free[b]) continue;
        if (!_conflict(nodes[group[a]], pos[a], nodes[group[b]], pos[b])) {
          continue;
        }
        conflicts = true;
        var diff =
            base[b] + shift[b] / radii[b] - base[a] - shift[a] / radii[a];
        diff = math.atan2(math.sin(diff), math.cos(diff));
        final dir = diff >= 0 ? 1.0 : -1.0;
        final each = free[a] && free[b] ? _step : 2 * _step;
        if (free[a]) push[a] -= dir * each;
        if (free[b]) push[b] += dir * each;
      }
    }
    if (!conflicts) break;
    var moved = false;
    for (var k = 0; k < n; k++) {
      if (push[k] == 0) continue;
      final next = (shift[k] + push[k]).clamp(-cap, cap);
      if (next != shift[k]) moved = true;
      shift[k] = next;
      pos[k] = at(k);
    }
    if (!moved) break;
  }

  for (var k = 0; k < n; k++) {
    final from = nodes[group[k]].position;
    final to = pos[k];
    if (math.sqrt(math.pow(to.x - from.x, 2) + math.pow(to.y - from.y, 2)) >
        1e-9) {
      moves[nodes[group[k]].id] = to;
    }
  }
}

LRect _labelOf(ConstellationTidyNode n, LPoint p) {
  final cy = p.y + n.radius + n.labelSize.h / 2;
  return (
    left: p.x - n.labelSize.w / 2,
    top: cy - n.labelSize.h / 2,
    right: p.x + n.labelSize.w / 2,
    bottom: cy + n.labelSize.h / 2,
  );
}

bool _nodeHitsLabel(ConstellationTidyNode n, LPoint p, LRect box) {
  final nx = p.x.clamp(box.left, box.right);
  final ny = p.y.clamp(box.top, box.bottom);
  return math.sqrt(math.pow(p.x - nx, 2) + math.pow(p.y - ny, 2)) < n.radius;
}

bool _conflict(
  ConstellationTidyNode a,
  LPoint pa,
  ConstellationTidyNode b,
  LPoint pb,
) {
  final d = math.sqrt(math.pow(pa.x - pb.x, 2) + math.pow(pa.y - pb.y, 2));
  if (d < a.radius + b.radius) return true;
  final la = _labelOf(a, pa);
  final lb = _labelOf(b, pb);
  if (la.left < lb.right &&
      lb.left < la.right &&
      la.top < lb.bottom &&
      lb.top < la.bottom) {
    return true;
  }
  return _nodeHitsLabel(a, pa, lb) || _nodeHitsLabel(b, pb, la);
}
