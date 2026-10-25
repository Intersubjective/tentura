import 'dart:math' as math;

import 'layout/layout_geometry.dart';

/// Side of the square minimap, in logical points.
const kConstellationMinimapSize = 104.0;

/// Maps the Field's scene coordinates into the minimap square and back.
///
/// Fitted to the people alone (never the camera), with one scale for both
/// axes, so the field keeps its shape and sits centred in the square.
class ConstellationMinimapProjection {
  factory ConstellationMinimapProjection.fromPoints(Iterable<LPoint> points) {
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
      return const ConstellationMinimapProjection._((x: 0, y: 0), 1);
    }
    final extent = math.max(maxX - minX, maxY - minY);
    return ConstellationMinimapProjection._(
      (x: (minX + maxX) / 2, y: (minY + maxY) / 2),
      extent > 0 ? kConstellationMinimapSize / extent : 1,
    );
  }

  const ConstellationMinimapProjection._(this._centre, this._scale);

  /// The scene point shown at the middle of the minimap.
  final LPoint _centre;

  /// Minimap points per scene unit.
  final double _scale;

  static const _half = kConstellationMinimapSize / 2;

  LPoint worldToMinimap(LPoint world) => (
    x: _snap(_half + (world.x - _centre.x) * _scale),
    y: _snap(_half + (world.y - _centre.y) * _scale),
  );

  /// Rounding must not push an edge person a hair outside the square.
  static double _snap(double v) {
    const tolerance = 1e-9;
    if (v < 0 && v > -tolerance) return 0;
    const side = kConstellationMinimapSize;
    if (v > side && v < side + tolerance) return side;
    return v;
  }

  LPoint minimapToWorld(LPoint point) => (
    x: _centre.x + (point.x - _half) / _scale,
    y: _centre.y + (point.y - _half) / _scale,
  );

  /// The camera's [viewport] (in scene coordinates) on the minimap, clipped
  /// to the square when the camera shows more than the field.
  LRect frameOf(LRect viewport) {
    double clamp(double v) => v.clamp(0, kConstellationMinimapSize);
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
