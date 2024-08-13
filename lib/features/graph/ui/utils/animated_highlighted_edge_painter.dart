import 'dart:ui' as ui;
import 'package:flutter/animation.dart';
import 'package:flutter/rendering.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import '../../domain/entity/edge_details.dart';
import '../../domain/entity/node_details.dart';

class AnimatedHighlightedEdgePainter
    implements AnimatedEdgePainter<NodeDetails, EdgeDetails<NodeDetails>> {
  const AnimatedHighlightedEdgePainter({
    required this.animation,
    required this.highlightColor,
    required this.highlightRadius,
    this.isAnimated = true,
  });

  @override
  final Animation<double> animation;

  final bool isAnimated;
  final Color highlightColor;
  final double highlightRadius;

  @override
  void paint(
    Canvas canvas,
    EdgeDetails<NodeDetails> edge,
    Offset src,
    Offset dst,
  ) {
    if (isAnimated) {
      /// Shifts animation "back" by the width of the highlight, to prevent
      /// it from popping unexpectedly out of nowhere at the beginning of the edge
      final animationShifted =
          animation.value * (1 + highlightRadius * 2) - highlightRadius * 2;
      canvas.drawLine(
        src,
        dst,
        Paint()
          ..strokeWidth = edge.strokeWidth
          ..shader = ui.Gradient.linear(
            src,
            dst,
            [edge.color, highlightColor, edge.color],
            [0, highlightRadius, 2 * highlightRadius],
            TileMode.clamp,
            Matrix4.translationValues(
              (dst.dx - src.dx) * animationShifted,
              (dst.dy - src.dy) * animationShifted,
              0,
            ).storage,
          ),
      );
    } else {
      canvas.drawLine(
        src,
        dst,
        Paint()
          ..color = edge.color
          ..strokeWidth = edge.strokeWidth,
      );
    }
  }
}
