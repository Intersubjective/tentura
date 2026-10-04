import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/rendering.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import '../../domain/entity/edge_details.dart';
import '../../domain/entity/node_details.dart';
import 'graph_edge_stroke.dart';

class AnimatedHighlightedEdgePainter
    implements AnimatedEdgePainter<NodeDetails, EdgeDetails> {
  const AnimatedHighlightedEdgePainter({
    required this.animation,
    required this.highlightRadius,
    this.isAnimated = true,
  });

  @override
  final Animation<double> animation;

  final bool isAnimated;
  final double highlightRadius;

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
    EdgeDetails edge,
    Offset src,
    Offset dst,
  ) {
    if (isAnimated) {
      /// Shifts animation "back" by the width of the highlight, to prevent
      /// it from popping unexpectedly out of nowhere at the beginning of the edge
      final animationShifted =
          animation.value * (1 + highlightRadius * 2) - highlightRadius * 2;
      GraphEdgeStroke.drawLine(
        canvas,
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
        edge.pattern,
      );
      if (edge.isReciprocal) {
        _paintReciprocalHighlight(
          canvas,
          src: dst,
          dst: src,
          edge: edge,
          animationShifted: animationShifted,
        );
      }
    } else {
      GraphEdgeStroke.drawLine(
        canvas,
        src,
        dst,
        Paint()
          ..color = edge.color
          ..strokeWidth = edge.strokeWidth,
        edge.pattern,
      );
    }
    _paintMarks(canvas, edge, src, dst);
  }

  /// Non-color cues drawn on top of the stroke: ✕ for negative edges and
  /// arrowheads (tips stop at the node rim so the avatar does not hide them).
  void _paintMarks(Canvas canvas, EdgeDetails edge, Offset src, Offset dst) {
    final (start, end) = GraphEdgeStroke.trim(
      src,
      dst,
      insetA: edge.source.size / 2 + _arrowGap,
      insetB: edge.destination.size / 2 + _arrowGap,
    );
    if (edge.crossMark) {
      GraphEdgeStroke.drawCrossMark(
        canvas,
        start,
        end,
        Paint()
          ..color = edge.color
          ..strokeWidth = edge.strokeWidth,
      );
    }
    if (edge.arrowAtDestination) {
      GraphEdgeStroke.drawArrowHead(
        canvas,
        tip: end,
        from: start,
        color: edge.color,
        strokeWidth: edge.strokeWidth,
      );
    }
    if (edge.arrowAtSource) {
      GraphEdgeStroke.drawArrowHead(
        canvas,
        tip: start,
        from: end,
        color: edge.color,
        strokeWidth: edge.strokeWidth,
      );
    }
  }

  static const _arrowGap = 2.0;

  void _paintReciprocalHighlight(
    Canvas canvas, {
    required Offset src,
    required Offset dst,
    required EdgeDetails edge,
    required double animationShifted,
  }) {
    final transparent = edge.color.withValues(alpha: 0);
    GraphEdgeStroke.drawLine(
      canvas,
      src,
      dst,
      Paint()
        ..strokeWidth = edge.strokeWidth
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.linear(
          src,
          dst,
          [transparent, _highlightFor(edge.color), transparent],
          [0, highlightRadius, 2 * highlightRadius],
          TileMode.clamp,
          Matrix4.translationValues(
            (dst.dx - src.dx) * animationShifted,
            (dst.dy - src.dy) * animationShifted,
            0,
          ).storage,
        ),
      edge.pattern,
    );
  }
}
