import 'dart:ui';

import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'constellation_presentation_frame.dart';

final class ConstellationPresentationFrameHolder {
  ConstellationPresentationFrame? frame;
}

/// Returns the node for a tap at [p] (viewport px), or null for "no opinion".
///
/// A label wins first (labels never overlap). Otherwise the visible bodies
/// under [p] decide, then the tap targets: each a circle of at least
/// `minTarget` on screen around the node, so a zoomed-out node stays easy to
/// hit (#640). Among several candidates of the same pass the node whose
/// centre is nearest to [p] wins, not the one painted last; only an exact
/// tie goes to the later paint order.
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

  return _nearestHit(f, p, (id, body) => body.contains(p)) ??
      _nearestHit(f, p, (id, body) {
        final target = f.tapTargets[id];
        return target != null && constellationTapTargetContains(target, p);
      });
}

/// Whether [p] is inside the round tap target drawn by [target]'s bounds.
bool constellationTapTargetContains(Rect target, Offset p) =>
    (p - target.center).distance <= target.shortestSide / 2;

GraphNodeId? _nearestHit(
  ConstellationPresentationFrame f,
  Offset p,
  bool Function(GraphNodeId id, Rect body) hits,
) {
  GraphNodeId? bestId;
  var bestDistSq = double.infinity;

  for (var i = 0; i < f.paintOrder.length; i++) {
    final id = f.paintOrder[i];
    final body = f.bodies[id];
    if (body == null || !hits(id, body)) {
      continue;
    }
    final d = (body.center - p).distanceSquared;
    if (d < bestDistSq - 1e-9) {
      bestDistSq = d;
      bestId = id;
    } else if ((d - bestDistSq).abs() <= 1e-9) {
      // An exact tie goes to the later paint order.
      bestId = id;
    }
  }

  return bestId;
}
