import 'package:flutter/material.dart';

import 'edge_stroke_recording.dart';

/// Captures geometry as drawn, including individual contours of dashed paths.
class EndpointRecordingCanvas extends RecordingEdgeCanvas {
  // Circles are decorations and never count as stroke geometry.
  final circles = <(Offset, double)>[];
  final strokes = <(Offset, Offset)>[];
  final filledPathBounds = <Rect>[];

  @override
  void drawCircle(Offset centre, double radius, Paint paint) {
    if (paint.color.a > 0) circles.add((centre, radius));
  }

  @override
  void drawLine(Offset a, Offset b, Paint paint) {
    if (paint.color.a > 0) strokes.add((a, b));
  }

  @override
  void drawPath(Path path, Paint paint) {
    if (paint.color.a <= 0) return;
    if (paint.style == PaintingStyle.fill) {
      filledPathBounds.add(path.getBounds());
      return;
    }
    for (final metric in path.computeMetrics()) {
      if (metric.length > 0) {
        strokes.add((
          metric.getTangentForOffset(0)!.position,
          metric.getTangentForOffset(metric.length)!.position,
        ));
      }
    }
  }
}
