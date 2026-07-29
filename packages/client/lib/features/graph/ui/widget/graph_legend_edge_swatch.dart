import 'package:flutter/material.dart';

/// Small horizontal edge sample for the graph legend.
class GraphLegendEdgeSwatch extends StatelessWidget {
  const GraphLegendEdgeSwatch({
    required this.color,
    this.strokeWidth = 2,
    super.key,
  });

  final Color color;
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
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _EdgeSwatchPainter extends CustomPainter {
  const _EdgeSwatchPainter({
    required this.color,
    required this.strokeWidth,
  });

  final Color color;
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
  }

  @override
  bool shouldRepaint(covariant _EdgeSwatchPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}
