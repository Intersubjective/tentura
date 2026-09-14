import 'dart:ui';

import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'constellation_presentation_frame.dart';

final class ConstellationPresentationFrameHolder {
  ConstellationPresentationFrame? frame;
}

/// Returns the node for a tap at [p] (viewport px), or null for "no opinion".
GraphNodeId? resolveConstellationTap(
  ConstellationPresentationFrame f,
  Offset p,
) {
  for (var i = f.paintOrder.length - 1; i >= 0; i--) {
    final id = f.paintOrder[i];
    final label = f.labels[id];
    if (label != null && label.contains(p)) {
      return id;
    }
  }

  for (var i = f.paintOrder.length - 1; i >= 0; i--) {
    final id = f.paintOrder[i];
    final body = f.bodies[id];
    if (body != null && body.contains(p)) {
      return id;
    }
  }

  GraphNodeId? bestId;
  var bestDistSq = double.infinity;
  var bestPaintIndex = -1;

  for (var i = 0; i < f.paintOrder.length; i++) {
    final id = f.paintOrder[i];
    final target = f.tapTargets[id];
    final body = f.bodies[id];
    if (target == null || body == null || !target.contains(p)) {
      continue;
    }
    final d = (body.center - p).distanceSquared;
    if (d < bestDistSq - 1e-9) {
      bestDistSq = d;
      bestId = id;
      bestPaintIndex = i;
    } else if ((d - bestDistSq).abs() <= 1e-9 && i > bestPaintIndex) {
      bestId = id;
      bestPaintIndex = i;
    }
  }

  return bestId;
}
