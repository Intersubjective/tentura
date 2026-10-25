import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

import '../bloc/constellation_cubit.dart';

/// Every kind keeps a non-color cue: solid / dashed / dotted pattern, width,
/// `endDots` (request links end in dots on both ends) and `twin` (mutual
/// trust is two parallel strokes, one per direction).
typedef ConstellationEdgeStyle = ({
  Color color,
  double width,
  double dash,
  double gap,
  bool endDots,
  bool twin,
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

/// One [Path] holding the dashes of the circle of [radius] around [center]:
/// each [dash] long, [gap] apart, starting at the right-most point and going
/// clockwise. The dash length is stretched so a whole number of dashes closes
/// the circle; a circle with no radius draws nothing.
Path constellationDashedCirclePath(
  Offset center,
  double radius, {
  required double dash,
  required double gap,
}) {
  final path = Path();
  if (radius <= 0 || dash <= 0) {
    return path;
  }
  final circumference = 2 * math.pi * radius;
  final count = math.max(1, (circumference / (dash + gap)).round());
  final step = 2 * math.pi / count;
  final sweep = step * dash / (dash + gap);
  final rect = Rect.fromCircle(center: center, radius: radius);
  for (var i = 0; i < count; i++) {
    path.addArc(rect, i * step, sweep);
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
///
/// A [twin] edge is the same stroke twice, 1.5 stroke widths to either side
/// of `a → b`: two strokes of space between them, room for a path edge drawn
/// along the same pair to show through.
void paintConstellationEdgeStroke(
  Canvas canvas,
  Offset a,
  Offset b,
  Paint paint, {
  required double dash,
  required double gap,
  required bool endDots,
  Path? dashPath,
  bool twin = false,
}) {
  if (twin) {
    final delta = b - a;
    final length = delta.distance;
    if (length > 0) {
      final offset =
          Offset(-delta.dy / length, delta.dx / length) *
          (paint.strokeWidth * 1.5);
      for (final side in [offset, -offset]) {
        canvas
          ..save()
          ..translate(side.dx, side.dy);
        paintConstellationEdgeStroke(
          canvas,
          a,
          b,
          paint,
          dash: dash,
          gap: gap,
          endDots: endDots,
          dashPath: dashPath,
        );
        canvas.restore();
      }
      return;
    }
  }
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
    twin: false,
  ),
  ConstellationEdgeKind.tier2Path => (
    color: tt.graphEdgePath,
    width: 2.0,
    dash: 6,
    gap: 4,
    endDots: false,
    twin: false,
  ),
  ConstellationEdgeKind.ringStub => (
    color: tt.graphEdgePath,
    width: 1.5,
    dash: 2,
    gap: 4,
    endDots: false,
    twin: false,
  ),
  ConstellationEdgeKind.webForwarded => (
    color: scheme.tertiary,
    width: 1.5,
    dash: 2,
    gap: 4,
    endDots: false,
    twin: false,
  ),
  ConstellationEdgeKind.webInside => (
    color: scheme.tertiary,
    width: 1.5,
    dash: 0,
    gap: 0,
    endDots: false,
    twin: false,
  ),
  ConstellationEdgeKind.draftRecipient => (
    color: scheme.tertiary,
    width: 1.5,
    dash: 6,
    gap: 4,
    endDots: false,
    twin: false,
  ),
  ConstellationEdgeKind.attachment => (
    color: scheme.secondary,
    width: 1.5,
    dash: 0,
    gap: 0,
    endDots: true,
    twin: false,
  ),
  ConstellationEdgeKind.grewFrom => (
    color: scheme.secondary,
    width: 1.5,
    dash: 6,
    gap: 4,
    endDots: false,
    twin: false,
  ),
  // A temporary person to the Request that made them visible: thin, dashed,
  // in the colour of the person's dashed outline.
  ConstellationEdgeKind.temporaryPresence => (
    color: tt.graphEdgePath,
    width: 1,
    dash: 4,
    gap: 4,
    endDots: false,
    twin: false,
  ),
  // The colour of the mutual trust ring (#643), thinner than a path.
  ConstellationEdgeKind.mutualTrust => (
    color: scheme.primary,
    width: 1.25,
    dash: 0,
    gap: 0,
    endDots: false,
    twin: true,
  ),
};
