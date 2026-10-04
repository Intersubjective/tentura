import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_edge_style.dart';

import '../utils/graph_edge_stroke.dart';
import '../utils/graph_edge_style.dart';

/// Small horizontal edge sample for the graph legend, drawn from the same
/// [GraphEdgeStyle] and [GraphEdgeStroke] geometry as the graph itself.
class GraphLegendEdgeSwatch extends StatelessWidget {
  const GraphLegendEdgeSwatch({
    required this.style,
    this.color,
    this.arrowAtStart = false,
    this.arrowAtEnd = false,
    super.key,
  });

  final GraphEdgeStyle style;

  /// Overrides [style]'s color (e.g. a dimmed sample for a hidden layer).
  final Color? color;
  final bool arrowAtStart;
  final bool arrowAtEnd;

  static const _width = 48.0;
  static const _height = 16.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _width,
      height: _height,
      child: CustomPaint(
        painter: _EdgeSwatchPainter(
          style: style,
          color: color ?? style.color,
          arrowAtStart: arrowAtStart,
          arrowAtEnd: arrowAtEnd,
        ),
      ),
    );
  }
}

class _EdgeSwatchPainter extends CustomPainter {
  const _EdgeSwatchPainter({
    required this.style,
    required this.color,
    required this.arrowAtStart,
    required this.arrowAtEnd,
  });

  final GraphEdgeStyle style;
  final Color color;
  final bool arrowAtStart;
  final bool arrowAtEnd;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 2.0;
    final start = Offset(inset, size.height / 2);
    final end = Offset(size.width - inset, size.height / 2);
    final paint = Paint()
      ..color = color
      ..strokeWidth = style.width;

    GraphEdgeStroke.drawLine(canvas, start, end, paint, style.pattern);
    if (style.crossMark) {
      GraphEdgeStroke.drawCrossMark(canvas, start, end, paint);
    }
    if (arrowAtEnd) {
      GraphEdgeStroke.drawArrowHead(
        canvas,
        tip: end,
        from: start,
        color: color,
        strokeWidth: style.width,
      );
    }
    if (arrowAtStart) {
      GraphEdgeStroke.drawArrowHead(
        canvas,
        tip: start,
        from: end,
        color: color,
        strokeWidth: style.width,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EdgeSwatchPainter oldDelegate) =>
      oldDelegate.style != style ||
      oldDelegate.color != color ||
      oldDelegate.arrowAtStart != arrowAtStart ||
      oldDelegate.arrowAtEnd != arrowAtEnd;
}

/// Constellation legend sample, drawn with the canvas's own stroke routine
/// ([paintConstellationEdgeStroke]) from the same [ConstellationEdgeStyle].
class GraphLegendConstellationEdgeSwatch extends StatelessWidget {
  const GraphLegendConstellationEdgeSwatch({
    required this.style,
    super.key,
  });

  final ConstellationEdgeStyle style;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return CustomPaint(
      size: Size(tt.avatarSize, tt.iconSize),
      painter: _ConstellationEdgeSwatchPainter(style: style),
    );
  }
}

class _ConstellationEdgeSwatchPainter extends CustomPainter {
  const _ConstellationEdgeSwatchPainter({required this.style});

  final ConstellationEdgeStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = style.color
      ..strokeWidth = style.width
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    final inset = style.endDots ? style.width * 2 : style.width;
    paintConstellationEdgeStroke(
      canvas,
      Offset(inset, size.height / 2),
      Offset(size.width - inset, size.height / 2),
      paint,
      dash: style.dash,
      gap: style.gap,
      endDots: style.endDots,
    );
  }

  @override
  bool shouldRepaint(covariant _ConstellationEdgeSwatchPainter oldDelegate) =>
      oldDelegate.style != style;
}
