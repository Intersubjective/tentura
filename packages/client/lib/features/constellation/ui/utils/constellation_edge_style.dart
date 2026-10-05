import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

import '../bloc/constellation_cubit.dart';

/// Every kind keeps a non-color cue: solid / dashed / dotted pattern, width,
/// and `endDots` (request links end in dots on both ends).
typedef ConstellationEdgeStyle = ({
  Color color,
  double width,
  double dash,
  double gap,
  bool endDots,
});

/// Strokes `a → b` the way the edge style says, with [paint] already carrying the
/// color and (camera-scaled) stroke width. Shared by the Constellation canvas
/// and its legend so samples match the graph.
void paintConstellationEdgeStroke(
  Canvas canvas,
  Offset a,
  Offset b,
  Paint paint, {
  required double dash,
  required double gap,
  required bool endDots,
}) {
  if (dash <= 0) {
    canvas.drawLine(a, b, paint);
  } else {
    final delta = b - a;
    final length = delta.distance;
    if (length > 0) {
      final direction = delta / length;
      var travelled = 0.0;
      while (travelled < length) {
        final dashEnd = math.min(travelled + dash, length);
        canvas.drawLine(
          a + direction * travelled,
          a + direction * dashEnd,
          paint,
        );
        travelled += dash + gap;
      }
    }
  }
  if (endDots) {
    final dotPaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final radius = paint.strokeWidth * 1.6;
    canvas
      ..drawCircle(a, radius, dotPaint)
      ..drawCircle(b, radius, dotPaint);
  }
}

ConstellationEdgeStyle constellationEdgeStyle(
  ConstellationEdgeKind kind,
  TenturaTokens tt,
  ColorScheme scheme,
) => switch (kind) {
  ConstellationEdgeKind.tier1Path => (
    color: tt.graphEdgePath,
    width: 2.0,
    dash: 0,
    gap: 0,
    endDots: false,
  ),
  ConstellationEdgeKind.tier2Path => (
    color: tt.graphEdgePath,
    width: 2.0,
    dash: 6,
    gap: 4,
    endDots: false,
  ),
  ConstellationEdgeKind.ringStub => (
    color: tt.graphEdgePath,
    width: 1.5,
    dash: 2,
    gap: 4,
    endDots: false,
  ),
  ConstellationEdgeKind.webForwarded => (
    color: scheme.tertiary,
    width: 1.5,
    dash: 2,
    gap: 4,
    endDots: false,
  ),
  ConstellationEdgeKind.webInside => (
    color: scheme.tertiary,
    width: 1.5,
    dash: 0,
    gap: 0,
    endDots: false,
  ),
  ConstellationEdgeKind.draftRecipient => (
    color: scheme.tertiary,
    width: 1.5,
    dash: 6,
    gap: 4,
    endDots: false,
  ),
  ConstellationEdgeKind.attachment => (
    color: scheme.secondary,
    width: 1.5,
    dash: 0,
    gap: 0,
    endDots: true,
  ),
};
