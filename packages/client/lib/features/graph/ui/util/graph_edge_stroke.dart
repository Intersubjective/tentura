import 'dart:math' as math;
import 'dart:ui';

import '../../domain/entity/graph_edge_pattern.dart';

/// Geometry shared by the graph edge painter and the legend swatches: dash /
/// dot pattern, the ✕ mark for negative edges and direction arrowheads.
///
/// Sizes scale with the stroke width so thick and thin edges keep their
/// proportions.
abstract final class GraphEdgeStroke {
  /// Strokes `a → b` with [paint] (its `strokeWidth`, color or shader) using
  /// [pattern].
  static void drawLine(
    Canvas canvas,
    Offset a,
    Offset b,
    Paint paint,
    GraphEdgePattern pattern,
  ) {
    switch (pattern) {
      case GraphEdgePattern.solid:
        canvas.drawLine(a, b, paint);
      case GraphEdgePattern.dashed:
        final w = paint.strokeWidth;
        _drawDashes(
          canvas,
          a,
          b,
          paint,
          dash: math.max(6, w * 4),
          gap: math.max(4, w * 2.5),
        );
      case GraphEdgePattern.dotted:
        final w = paint.strokeWidth;
        final dotPaint = Paint()
          ..style = PaintingStyle.fill
          ..color = paint.color
          ..shader = paint.shader
          ..blendMode = paint.blendMode
          ..isAntiAlias = true;
        final delta = b - a;
        final length = delta.distance;
        if (length <= 0) return;
        final step = w * 2.6 + 1;
        final direction = delta / length;
        for (var t = step / 2; t < length; t += step) {
          canvas.drawCircle(a + direction * t, w / 2 + 0.25, dotPaint);
        }
    }
  }

  /// Draws a ✕ centered on the midpoint of `a → b`, rotated 45° to the edge.
  static void drawCrossMark(Canvas canvas, Offset a, Offset b, Paint paint) {
    final delta = b - a;
    final length = delta.distance;
    if (length <= 0) return;
    final direction = delta / length;
    final normal = Offset(-direction.dy, direction.dx);
    final arm = 3 + paint.strokeWidth * 1.5;
    final mid = a + delta / 2;
    final d1 = (direction + normal) * (arm / math.sqrt2);
    final d2 = (direction - normal) * (arm / math.sqrt2);
    final crossPaint = Paint()
      ..color = paint.color
      ..strokeWidth = paint.strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    canvas
      ..drawLine(mid - d1, mid + d1, crossPaint)
      ..drawLine(mid - d2, mid + d2, crossPaint);
  }

  /// Filled arrowhead whose tip sits at [tip], pointing away from [from].
  static void drawArrowHead(
    Canvas canvas, {
    required Offset tip,
    required Offset from,
    required Color color,
    required double strokeWidth,
  }) {
    final delta = tip - from;
    final length = delta.distance;
    if (length <= 0) return;
    final direction = delta / length;
    final normal = Offset(-direction.dy, direction.dx);
    final headLength = arrowHeadLength(strokeWidth);
    final halfWidth = headLength * 0.5;
    final base = tip - direction * headLength;
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(
          base.dx + normal.dx * halfWidth,
          base.dy + normal.dy * halfWidth,
        )
        ..lineTo(
          base.dx - normal.dx * halfWidth,
          base.dy - normal.dy * halfWidth,
        )
        ..close(),
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
  }

  static double arrowHeadLength(double strokeWidth) => 6 + strokeWidth * 2;

  /// Moves `a` and `b` toward each other by [insetA] / [insetB] (e.g. node
  /// radii), keeping them unchanged when the segment is too short.
  static (Offset, Offset) trim(
    Offset a,
    Offset b, {
    required double insetA,
    required double insetB,
  }) {
    final delta = b - a;
    final length = delta.distance;
    if (length <= insetA + insetB) return (a, b);
    final direction = delta / length;
    return (a + direction * insetA, b - direction * insetB);
  }

  static void _drawDashes(
    Canvas canvas,
    Offset a,
    Offset b,
    Paint paint, {
    required double dash,
    required double gap,
  }) {
    final delta = b - a;
    final length = delta.distance;
    if (length <= 0) return;
    final direction = delta / length;
    var travelled = 0.0;
    while (travelled < length) {
      final end = math.min(travelled + dash, length);
      canvas.drawLine(a + direction * travelled, a + direction * end, paint);
      travelled += dash + gap;
    }
  }
}
