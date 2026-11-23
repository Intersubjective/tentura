import 'dart:math' as math;
import 'dart:ui';

/// Moves [wanted] off every rect in [labels] it overlaps, by the shortest
/// shift that clears them all, preferring a result inside [bounds].
/// After fit-all, [fittedViewport] keeps the chip accessible.
Rect clearMagnetOfLabels(
  Rect wanted,
  Iterable<Rect> labels, {
  required Rect bounds,
  Rect? fittedViewport,
  double gap = 4,
}) {
  final obstacles = [for (final label in labels) label.inflate(gap)];
  bool clear(Rect r) => !obstacles.any(r.overlaps);

  var limit = fittedViewport ?? bounds;
  if (fittedViewport != null) {
    // An oversized control can still fit on the other axis.
    limit = Rect.fromLTRB(
      wanted.width > limit.width ? wanted.left : limit.left,
      wanted.height > limit.height ? wanted.top : limit.top,
      wanted.width > limit.width ? wanted.right : limit.right,
      wanted.height > limit.height ? wanted.bottom : limit.bottom,
    );
  }
  bool inside(Rect r) =>
      r.left >= limit.left &&
      r.top >= limit.top &&
      r.right <= limit.right &&
      r.bottom <= limit.bottom;
  if ((fittedViewport == null || inside(wanted)) && clear(wanted)) {
    return wanted;
  }

  // Each step is also tried pulled back onto the map, so a label near the map
  // edge still leaves a clear spot that is fully visible.
  final candidatesFrom = fittedViewport == null
      ? obstacles.where(wanted.overlaps)
      : obstacles.where(limit.overlaps);
  final fittedPosition = fittedViewport == null ? null : _within(wanted, limit);
  final candidates = <Rect>[
    ?fittedPosition,
    for (final o in candidatesFrom)
      for (final step in [
        wanted.shift(Offset(0, o.top - wanted.bottom)),
        wanted.shift(Offset(0, o.bottom - wanted.top)),
        wanted.shift(Offset(o.left - wanted.right, 0)),
        wanted.shift(Offset(o.right - wanted.left, 0)),
      ]) ...[step, _within(step, limit)],
  ]..sort((a, b) => _shift(wanted, a).compareTo(_shift(wanted, b)));

  for (final candidate in candidates) {
    if (inside(candidate) && clear(candidate)) return candidate;
  }
  // Fit-all keeps the control accessible even if no clear spot fits.
  if (fittedPosition != null) return fittedPosition;
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
