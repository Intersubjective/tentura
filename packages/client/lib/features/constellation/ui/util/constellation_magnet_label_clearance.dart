import 'dart:math' as math;
import 'dart:ui';

/// Moves [wanted] off every rect in [labels] it overlaps, by the shortest
/// shift that clears them all, preferring a result inside [bounds]. A rect
/// that overlaps nothing is returned untouched, so a magnet away from the
/// node labels stays exactly where it was dropped.
Rect clearMagnetOfLabels(
  Rect wanted,
  Iterable<Rect> labels, {
  required Rect bounds,
  double gap = 4,
}) {
  final obstacles = [for (final label in labels) label.inflate(gap)];
  bool clear(Rect r) => !obstacles.any(r.overlaps);
  if (clear(wanted)) return wanted;

  // Each step is also tried pulled back onto the map, so a label near the map
  // edge still leaves a clear spot that is fully visible.
  final candidates = <Rect>[
    for (final o in obstacles.where(wanted.overlaps))
      for (final step in [
        wanted.shift(Offset(0, o.top - wanted.bottom)),
        wanted.shift(Offset(0, o.bottom - wanted.top)),
        wanted.shift(Offset(o.left - wanted.right, 0)),
        wanted.shift(Offset(o.right - wanted.left, 0)),
      ]) ...[step, _within(step, bounds)],
  ]..sort((a, b) => _shift(wanted, a).compareTo(_shift(wanted, b)));

  bool inside(Rect r) =>
      r.left >= bounds.left &&
      r.top >= bounds.top &&
      r.right <= bounds.right &&
      r.bottom <= bounds.bottom;
  for (final candidate in candidates) {
    if (clear(candidate) && inside(candidate)) return candidate;
  }
  for (final candidate in candidates) {
    if (clear(candidate)) return candidate;
  }
  return wanted;
}

double _shift(Rect from, Rect to) =>
    math.max((to.left - from.left).abs(), (to.top - from.top).abs());

Rect _within(Rect r, Rect bounds) => r.shift(
  Offset(
    r.left < bounds.left
        ? bounds.left - r.left
        : math.min(0, bounds.right - r.right),
    r.top < bounds.top
        ? bounds.top - r.top
        : math.min(0, bounds.bottom - r.bottom),
  ),
);
