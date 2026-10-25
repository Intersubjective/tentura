import 'package:flutter/material.dart';

import '../utils/constellation_edge_style.dart';

/// The dashed ring around a temporary person's node. Fills the node it sits
/// on and takes no pointer events.
class ConstellationTemporaryOutline extends StatelessWidget {
  const ConstellationTemporaryOutline({
    required this.color,
    required this.dash,
    required this.gap,
    required this.strokeWidth,
    super.key,
  });

  final Color color;
  final double dash;
  final double gap;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(
      painter: _OutlinePainter(
        color: color,
        dash: dash,
        gap: gap,
        strokeWidth: strokeWidth,
      ),
    ),
  );
}

class _OutlinePainter extends CustomPainter {
  const _OutlinePainter({
    required this.color,
    required this.dash,
    required this.gap,
    required this.strokeWidth,
  });

  final Color color;
  final double dash;
  final double gap;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      constellationDashedCirclePath(
        size.center(Offset.zero),
        size.shortestSide / 2 - strokeWidth / 2,
        dash: dash,
        gap: gap,
      ),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_OutlinePainter oldDelegate) =>
      color != oldDelegate.color ||
      dash != oldDelegate.dash ||
      gap != oldDelegate.gap ||
      strokeWidth != oldDelegate.strokeWidth;
}
