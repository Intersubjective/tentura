import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

enum ConstellationDetailLevel { normal, overview }

const kConstellationNormalDetailScale = 0.85;
const kConstellationOverviewDetailScale = 0.70;

ConstellationDetailLevel nextConstellationDetailLevel(
  double cameraScale,
  ConstellationDetailLevel previous,
) {
  if (cameraScale >= kConstellationNormalDetailScale) {
    return ConstellationDetailLevel.normal;
  }
  if (cameraScale < kConstellationOverviewDetailScale) {
    return ConstellationDetailLevel.overview;
  }
  return previous;
}

/// Detail policy for [ConstellationFrameNodeInput.labelCandidate] (R03b sets this
/// before calling [computeConstellationPresentationFrame]).
bool constellationLabelCandidateForDetail({
  required ConstellationDetailLevel detail,
  required int priority,
  required int ring,
}) {
  switch (detail) {
    case ConstellationDetailLevel.normal:
      return true;
    case ConstellationDetailLevel.overview:
      if (priority <= 1) return true;
      if (priority == 2 && ring <= 1) return true;
      return false;
  }
}

@immutable
final class ConstellationFrameNodeInput {
  const ConstellationFrameNodeInput({
    required this.id,
    required this.centre,
    required this.bodyDiameter,
    required this.badgeOverhang,
    required this.labelSize,
    required this.priority,
    required this.ring,
    required this.labelCandidate,
  });

  final GraphNodeId id;
  final Offset centre;
  final double bodyDiameter;
  final double badgeOverhang;
  final Size labelSize;
  final int priority;
  final int ring;
  final bool labelCandidate;
}

@immutable
final class ConstellationFrameChipInput {
  const ConstellationFrameChipInput({
    required this.authorId,
    required this.authorGraphId,
    required this.size,
  });

  final String authorId;
  final GraphNodeId authorGraphId;
  final Size size;
}

@immutable
final class ConstellationPresentationFrame {
  const ConstellationPresentationFrame({
    required this.snapshot,
    required this.cameraRevision,
    required this.detail,
    required this.paintOrder,
    required this.bodies,
    required this.labels,
    required this.tapTargets,
    required this.chips,
    required this.forcedLabels,
  });

  final Object snapshot;
  final int cameraRevision;
  final ConstellationDetailLevel detail;
  final List<GraphNodeId> paintOrder;
  final Map<GraphNodeId, Rect> bodies;
  final Map<GraphNodeId, Rect> labels;
  final Map<GraphNodeId, Rect> tapTargets;
  final Map<String, Rect> chips;
  final Set<GraphNodeId> forcedLabels;
}

final class ConstellationPresentationFrameHolder {
  ConstellationPresentationFrame? frame;
}

ConstellationPresentationFrame computeConstellationPresentationFrame({
  required Object snapshot,
  required int cameraRevision,
  required ConstellationDetailLevel detail,
  required Size viewport,
  required List<ConstellationFrameNodeInput> nodesInPaintOrder,
  required List<ConstellationFrameChipInput> chips,
  required double gap,
  required double minTarget,
  required bool rtl,
}) {
  final viewportRect = Offset.zero & viewport;
  final paintOrder = nodesInPaintOrder.map((n) => n.id).toList(growable: false);

  final bodies = <GraphNodeId, Rect>{};
  final tapTargets = <GraphNodeId, Rect>{};
  final culled = <GraphNodeId>{};
  final decoratedBodies = <GraphNodeId, Rect>{};
  final nodeById = <GraphNodeId, ConstellationFrameNodeInput>{
    for (final n in nodesInPaintOrder) n.id: n,
  };

  for (final node in nodesInPaintOrder) {
    final body = Rect.fromCircle(
      center: node.centre,
      radius: node.bodyDiameter / 2,
    );
    final cullGrow =
        math.max(node.labelSize.width, node.labelSize.height) + gap;
    final cullRect = body.inflate(cullGrow);
    if (!cullRect.overlaps(viewportRect)) {
      culled.add(node.id);
      continue;
    }

    bodies[node.id] = body;
    tapTargets[node.id] = _symmetricMinTargetRect(body, minTarget);
    decoratedBodies[node.id] = Rect.fromLTRB(
      body.left - node.badgeOverhang,
      body.top - node.badgeOverhang,
      body.right + node.badgeOverhang,
      body.bottom,
    );
  }

  final occupied = <Rect>[];
  for (final id in paintOrder) {
    final decorated = decoratedBodies[id];
    if (decorated != null) {
      occupied.add(decorated.inflate(1));
    }
  }

  final placedChips = <String, Rect>{};
  final sortedChips = [...chips]..sort((a, b) => a.authorId.compareTo(b.authorId));

  for (final chip in sortedChips) {
    final author = nodeById[chip.authorGraphId];
    if (author == null || culled.contains(chip.authorGraphId)) {
      continue;
    }
    final body = bodies[chip.authorGraphId]!;
    final reservedBelow = _labelRectBelow(
      body,
      author.labelSize,
      gap,
    );
    final union = _rectUnion(body, reservedBelow);
    final candidates = [
      _chipRectBelow(union, chip.size, gap),
      _chipRectEnd(body, chip.size, gap, rtl: rtl),
      _chipRectStart(body, chip.size, gap, rtl: rtl),
      _chipRectAbove(body, chip.size, gap),
    ];
    final placed = _firstFittingCandidate(candidates, viewportRect, occupied) ??
        candidates.first;
    placedChips[chip.authorId] = placed;
    occupied.add(placed.inflate(1));
  }

  final labels = <GraphNodeId, Rect>{};
  final forcedLabels = <GraphNodeId>{};

  final labelNodes = nodesInPaintOrder
      .where((n) => !culled.contains(n.id))
      .where((n) => n.labelCandidate && n.labelSize != Size.zero)
      .toList()
    ..sort((a, b) {
      final pc = a.priority.compareTo(b.priority);
      if (pc != 0) return pc;
      final rc = a.ring.compareTo(b.ring);
      if (rc != 0) return rc;
      return a.id.compareTo(b.id);
    });

  for (final node in labelNodes) {
    final body = bodies[node.id]!;
    final candidates = [
      _labelRectBelow(body, node.labelSize, gap),
      _labelRectAbove(body, node.labelSize, gap),
      _labelRectEnd(body, node.labelSize, gap, rtl: rtl),
      _labelRectStart(body, node.labelSize, gap, rtl: rtl),
    ];
    final placed = _firstFittingCandidate(candidates, viewportRect, occupied);
    if (placed != null) {
      labels[node.id] = placed;
      occupied.add(placed.inflate(1));
    } else if (node.priority <= 1) {
      final forced = candidates.first;
      labels[node.id] = forced;
      forcedLabels.add(node.id);
      occupied.add(forced.inflate(1));
    }
  }

  return ConstellationPresentationFrame(
    snapshot: snapshot,
    cameraRevision: cameraRevision,
    detail: detail,
    paintOrder: paintOrder,
    bodies: bodies,
    labels: labels,
    tapTargets: tapTargets,
    chips: placedChips,
    forcedLabels: forcedLabels,
  );
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

Rect _symmetricMinTargetRect(Rect body, double minTarget) {
  final halfW = math.max(body.width / 2, minTarget / 2);
  final halfH = math.max(body.height / 2, minTarget / 2);
  return Rect.fromCenter(center: body.center, width: halfW * 2, height: halfH * 2);
}

Rect? _firstFittingCandidate(
  List<Rect> candidates,
  Rect viewport,
  List<Rect> occupied,
) {
  for (final candidate in candidates) {
    if (!_rectFullyInside(candidate, viewport)) continue;
    if (!_intersectsAny(candidate, occupied)) {
      return candidate;
    }
  }
  return null;
}

bool _rectFullyInside(Rect inner, Rect outer) {
  return inner.left >= outer.left &&
      inner.top >= outer.top &&
      inner.right <= outer.right &&
      inner.bottom <= outer.bottom;
}

bool _intersectsAny(Rect rect, List<Rect> others) {
  for (final other in others) {
    if (rect.overlaps(other)) return true;
  }
  return false;
}

Rect _rectUnion(Rect a, Rect b) {
  if (b.isEmpty) return a;
  return Rect.fromLTRB(
    math.min(a.left, b.left),
    math.min(a.top, b.top),
    math.max(a.right, b.right),
    math.max(a.bottom, b.bottom),
  );
}

Rect _labelRectBelow(Rect body, Size labelSize, double gap) {
  return Rect.fromLTWH(
    body.center.dx - labelSize.width / 2,
    body.bottom + gap,
    labelSize.width,
    labelSize.height,
  );
}

Rect _labelRectAbove(Rect body, Size labelSize, double gap) {
  return Rect.fromLTWH(
    body.center.dx - labelSize.width / 2,
    body.top - gap - labelSize.height,
    labelSize.width,
    labelSize.height,
  );
}

Rect _labelRectEnd(Rect body, Size labelSize, double gap, {required bool rtl}) {
  if (rtl) {
    return Rect.fromLTWH(
      body.left - gap - labelSize.width,
      body.center.dy - labelSize.height / 2,
      labelSize.width,
      labelSize.height,
    );
  }
  return Rect.fromLTWH(
    body.right + gap,
    body.center.dy - labelSize.height / 2,
    labelSize.width,
    labelSize.height,
  );
}

Rect _labelRectStart(Rect body, Size labelSize, double gap, {required bool rtl}) {
  if (rtl) {
    return Rect.fromLTWH(
      body.right + gap,
      body.center.dy - labelSize.height / 2,
      labelSize.width,
      labelSize.height,
    );
  }
  return Rect.fromLTWH(
    body.left - gap - labelSize.width,
    body.center.dy - labelSize.height / 2,
    labelSize.width,
    labelSize.height,
  );
}

Rect _chipRectBelow(Rect anchor, Size chipSize, double gap) {
  return Rect.fromLTWH(
    anchor.center.dx - chipSize.width / 2,
    anchor.bottom + gap,
    chipSize.width,
    chipSize.height,
  );
}

Rect _chipRectAbove(Rect body, Size chipSize, double gap) {
  return Rect.fromLTWH(
    body.center.dx - chipSize.width / 2,
    body.top - gap - chipSize.height,
    chipSize.width,
    chipSize.height,
  );
}

Rect _chipRectEnd(Rect body, Size chipSize, double gap, {required bool rtl}) {
  if (rtl) {
    return Rect.fromLTWH(
      body.left - gap - chipSize.width,
      body.center.dy - chipSize.height / 2,
      chipSize.width,
      chipSize.height,
    );
  }
  return Rect.fromLTWH(
    body.right + gap,
    body.center.dy - chipSize.height / 2,
    chipSize.width,
    chipSize.height,
  );
}

Rect _chipRectStart(Rect body, Size chipSize, double gap, {required bool rtl}) {
  if (rtl) {
    return Rect.fromLTWH(
      body.right + gap,
      body.center.dy - chipSize.height / 2,
      chipSize.width,
      chipSize.height,
    );
  }
  return Rect.fromLTWH(
    body.left - gap - chipSize.width,
    body.center.dy - chipSize.height / 2,
    chipSize.width,
    chipSize.height,
  );
}
