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
    required this.highlightRadius,
    this.isAnimated = true,
    this.showDirection = false,
  });

  @override
  final Animation<double> animation;

  final bool isAnimated;
  final double highlightRadius;

  /// When true, draws a small chevron near the destination node (forwards and
  /// genealogy only — trust edges stay undirected).
  final bool showDirection;

  /// Derives the traveling highlight from the edge's own color instead of a
  /// single fixed accent: a constant highlight (e.g. `ColorScheme.primary`)
  /// can land perceptually too close to a given edge color in some themes
  /// (light theme's `primary` and the "neutral"/info edge color are both
  /// muted blues of similar lightness), making the pulse invisible even
  /// though it animates correctly.
  static Color _highlightFor(Color base) {
    final hsl = HSLColor.fromColor(base);
    return hsl
        .withLightness((hsl.lightness + 0.3).clamp(0.0, 1.0))
        .withSaturation((hsl.saturation * 0.7).clamp(0.0, 1.0))
        .toColor();
  }

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
            [edge.color, _highlightFor(edge.color), edge.color],
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

    if (showDirection) {
      _paintArrowhead(
        canvas,
        src: src,
        dst: dst,
        srcRadius: edge.source.size / 2,
        dstRadius: edge.destination.size / 2,
        color: edge.color,
      );
    }
  }

  static void _paintArrowhead(
    Canvas canvas, {
    required Offset src,
    required Offset dst,
    required double srcRadius,
    required double dstRadius,
    required Color color,
  }) {
    const arrowLength = 8.0;
    const gap = 2.0;
    final delta = dst - src;
    final length = delta.distance;
    if (length <= 0) {
      return;
    }
    final minLength = srcRadius + dstRadius + gap + arrowLength;
    if (length < minLength) {
      return;
    }

    final direction = delta / length;
    final tip = dst - direction * (dstRadius + gap);
    final base = tip - direction * arrowLength;
    final perpendicular =
        Offset(-direction.dy, direction.dx) * (arrowLength * 0.45);

    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(base.dx + perpendicular.dx, base.dy + perpendicular.dy)
      ..lineTo(base.dx - perpendicular.dx, base.dy - perpendicular.dy)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }
}
