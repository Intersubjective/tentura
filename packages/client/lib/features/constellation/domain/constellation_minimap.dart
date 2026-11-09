import 'dart:math' as math;

import 'layout/layout_geometry.dart';

/// Side of the square minimap, in logical points.
const kConstellationMinimapSize = 104.0;

/// Inset from the minimap border so extreme people and dots stay fully inside
/// the framed area (FCP §M U1).
const kConstellationMinimapInset = 8.0;

/// Minimap-space clamp for the camera frame stroke so a 2px stroke stays off
/// the 1px outline-variant border (FCP §M U1).
const kConstellationMinimapFrameClampInset = 2.0;

/// World-space hysteresis when deciding whether the minimap chrome is needed:
/// roughly half a close-level person footprint so show/hide does not flicker
/// at the viewport edge.
const kConstellationMinimapVisibilityHysteresis = 28.0;

bool _footprintFullyInside(LRect viewport, LRect node) =>
    node.left >= viewport.left &&
    node.right <= viewport.right &&
    node.top >= viewport.top &&
    node.bottom <= viewport.bottom;

bool _footprintSpillsOutside(LRect viewport, LRect node) =>
    node.right > viewport.right ||
    node.left < viewport.left ||
    node.bottom > viewport.bottom ||
    node.top < viewport.top;

/// Whether the minimap toggle should stay mounted (some drawn node is off-screen).
///
/// When [currentlyShown], hides only after every [nodeBounds] sits inside the
/// viewport shrunk by [hysteresis]. When hidden, shows once any footprint
/// crosses the viewport grown by [hysteresis].
bool constellationMinimapNeededForViewport({
  required LRect viewport,
  required Iterable<LRect> nodeBounds,
  required bool currentlyShown,
  double hysteresis = kConstellationMinimapVisibilityHysteresis,
}) {
  final list = nodeBounds.toList();
  if (list.isEmpty) {
    return false;
  }
  if (currentlyShown) {
    return list.any((n) => !_footprintFullyInside(viewport, n));
  }
  final outer = (
    left: viewport.left - hysteresis,
    top: viewport.top - hysteresis,
    right: viewport.right + hysteresis,
    bottom: viewport.bottom + hysteresis,
  );
  return list.any((n) => _footprintSpillsOutside(outer, n));
}

/// Maps the Field's scene coordinates into the minimap square and back.
///
/// Fitted to the people alone (never the camera), with one scale for both
/// axes, so the field keeps its shape and sits centred in the square.
class ConstellationMinimapProjection {
  factory ConstellationMinimapProjection.fromPoints(
    Iterable<LPoint> points, {
    double inset = kConstellationMinimapInset,
  }) {
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    for (final p in points) {
      minX = math.min(minX, p.x);
      minY = math.min(minY, p.y);
      maxX = math.max(maxX, p.x);
      maxY = math.max(maxY, p.y);
    }
    if (minX > maxX) {
      return ConstellationMinimapProjection._(
        (x: 0, y: 0),
        1,
        inset: inset,
      );
    }
    final extent = math.max(maxX - minX, maxY - minY);
    final inner = math.max(0, kConstellationMinimapSize - 2 * inset).toDouble();
    return ConstellationMinimapProjection._(
      (x: (minX + maxX) / 2, y: (minY + maxY) / 2),
      extent > 0 ? inner / extent : 1,
      inset: inset,
    );
  }

  const ConstellationMinimapProjection._(
    this._centre,
    this._scale, {
    required this.inset,
  });

  /// The scene point shown at the middle of the minimap.
  final LPoint _centre;

  /// Minimap points per scene unit.
  final double _scale;

  /// Inset applied when `ConstellationMinimapProjection.fromPoints` built this projection.
  final double inset;

  static const _half = kConstellationMinimapSize / 2;

  double get _innerHalf => _half - inset;

  LPoint worldToMinimap(LPoint world) => (
    x: _snap(inset + _innerHalf + (world.x - _centre.x) * _scale),
    y: _snap(inset + _innerHalf + (world.y - _centre.y) * _scale),
  );

  /// Rounding must not push an edge person a hair outside the square.
  double _snap(double v) {
    const tolerance = 1e-9;
    final lo = inset;
    final hi = kConstellationMinimapSize - inset;
    if (v < lo && v > lo - tolerance) return lo;
    if (v > hi && v < hi + tolerance) return hi;
    return v;
  }

  LPoint minimapToWorld(LPoint point) => (
    x: _centre.x + (point.x - inset - _innerHalf) / _scale,
    y: _centre.y + (point.y - inset - _innerHalf) / _scale,
  );

  /// Scene displacement matching a drag of [delta] logical px on the minimap.
  LPoint minimapDeltaToWorld(LPoint delta) => (
    x: delta.x / _scale,
    y: delta.y / _scale,
  );

  /// The camera's [viewport] (in scene coordinates) on the minimap, clipped
  /// to the square when the camera shows more than the field.
  LRect frameOf(LRect viewport) {
    const fc = kConstellationMinimapFrameClampInset;
    double clamp(double v) => v.clamp(fc, kConstellationMinimapSize - fc);
    final topLeft = worldToMinimap((x: viewport.left, y: viewport.top));
    final bottomRight = worldToMinimap((
      x: viewport.right,
      y: viewport.bottom,
    ));
    return (
      left: clamp(topLeft.x),
      top: clamp(topLeft.y),
      right: clamp(bottomRight.x),
      bottom: clamp(bottomRight.y),
    );
  }
}
