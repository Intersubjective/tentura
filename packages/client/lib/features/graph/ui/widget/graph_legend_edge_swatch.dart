import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

/// Small horizontal edge sample for the graph legend.
class GraphLegendEdgeSwatch extends StatelessWidget {
  const GraphLegendEdgeSwatch({
    required this.color,
    this.directed = false,
    this.strokeWidth = 2,
    super.key,
  });

  final Color color;
  final bool directed;
  final double strokeWidth;

  static const _width = 48.0;
  static const _height = 16.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _width,
      height: _height,
      child: CustomPaint(
        painter: _EdgeSwatchPainter(
          color: color,
          directed: directed,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _EdgeSwatchPainter extends CustomPainter {
  const _EdgeSwatchPainter({
    required this.color,
    required this.directed,
    required this.strokeWidth,
  });

  final Color color;
  final bool directed;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 2.0;
    final start = Offset(inset, size.height / 2);
    final end = Offset(size.width - inset, size.height / 2);
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(start, end, paint);

    if (!directed) {
      return;
    }

    const arrowLength = 6.0;
    final direction = (end - start) / (end - start).distance;
    final tip = end;
    final base = tip - direction * arrowLength;
    final perpendicular = Offset(-direction.dy, direction.dx) * (arrowLength * 0.45);
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(base.dx + perpendicular.dx, base.dy + perpendicular.dy)
      ..lineTo(base.dx - perpendicular.dx, base.dy - perpendicular.dy)
      ..close();
    canvas.drawPath(path, paint..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(covariant _EdgeSwatchPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.directed != directed ||
      oldDelegate.strokeWidth != strokeWidth;
}
