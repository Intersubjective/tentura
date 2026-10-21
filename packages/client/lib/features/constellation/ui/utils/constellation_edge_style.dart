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

/// Shared by every edge's end dots: the painter is synchronous, so the color is
/// set right before each draw instead of allocating a Paint per edge.
final _endDotPaint = Paint()
  ..style = PaintingStyle.fill
  ..isAntiAlias = true;

/// Times dashed stroke geometry was constructed; tests pin it to prove edges
/// that did not move are not rebuilt.
@visibleForTesting
int get constellationEdgeDashPathBuildCount => _dashPathBuildCount;
var _dashPathBuildCount = 0;

/// One [Path] holding every dash of `a → b`, or null for a zero-length edge.
Path? constellationEdgeDashPath(
  Offset a,
  Offset b, {
  required double dash,
  required double gap,
}) {
  _dashPathBuildCount++;
  final delta = b - a;
  final length = delta.distance;
  if (length <= 0) {
    return null;
  }
  final direction = delta / length;
  final path = Path();
  var travelled = 0.0;
  while (travelled < length) {
    final dashEnd = math.min(travelled + dash, length);
    final from = a + direction * travelled;
    final to = a + direction * dashEnd;
    path
      ..moveTo(from.dx, from.dy)
      ..lineTo(to.dx, to.dy);
    travelled += dash + gap;
  }
  return path;
}

/// Strokes `a → b` the way the edge style says, with [paint] already carrying the
/// color and (camera-scaled) stroke width. Shared by the Constellation canvas
/// and its legend so samples match the graph.
///
/// A dashed edge is one [Path] (one draw call), not one `drawLine` per dash.
/// A caller that keeps the path of an edge between frames passes it as
/// [dashPath] (built by [constellationEdgeDashPath] for the same `a`, `b`,
/// [dash] and [gap]); otherwise it is built here.
void paintConstellationEdgeStroke(
  Canvas canvas,
  Offset a,
  Offset b,
  Paint paint, {
  required double dash,
  required double gap,
  required bool endDots,
  Path? dashPath,
}) {
  if (dash <= 0) {
    canvas.drawLine(a, b, paint);
  } else {
    final path =
        dashPath ?? constellationEdgeDashPath(a, b, dash: dash, gap: gap);
    if (path != null) {
      canvas.drawPath(path, paint);
    }
  }
  if (endDots) {
    _endDotPaint.color = paint.color;
    final radius = paint.strokeWidth * 1.6;
    canvas
      ..drawCircle(a, radius, _endDotPaint)
      ..drawCircle(b, radius, _endDotPaint);
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
  ConstellationEdgeKind.grewFrom => (
    color: scheme.secondary,
    width: 1.5,
    dash: 6,
    gap: 4,
    endDots: false,
  ),
};
