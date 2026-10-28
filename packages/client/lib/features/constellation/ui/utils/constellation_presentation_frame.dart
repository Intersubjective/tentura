import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/consts.dart';

/// How much the map shows at a camera scale: everything up close (`close`),
/// every label that fits (`district`, forcing none), or those without the
/// people beyond the nearest ring (`overview`, #595).
enum ConstellationDetailLevel { close, district, overview }

const kConstellationCloseDetailScale = 0.85;
const kConstellationDistrictDetailScale = 0.45;

/// Screen diameter of a person's dot at the overview (#595).
const kConstellationOverviewDotDiameter = 5.0;

/// Screen diameter of a person's initials circle at the district level (E3).
const kConstellationDistrictMarkerDiameter = 20.0;

/// With semantic zoom gated off, a map below this scale is a clean overview
/// of shapes and edges: no label and no overflow chip at all (#595). Fitting
/// a modest field already lands near 0.4, so a fitted map keeps its labels.
const kConstellationBareDetailScale = 0.3;

/// The level a settled camera [scale] shows: a pure function of the scale,
/// the same from either zoom direction.
ConstellationDetailLevel settledConstellationDetailLevel(double scale) {
  if (scale >= kConstellationCloseDetailScale) {
    return ConstellationDetailLevel.close;
  }
  if (scale >= kConstellationDistrictDetailScale) {
    return ConstellationDetailLevel.district;
  }
  return ConstellationDetailLevel.overview;
}

/// Whether the map drops every label and chip at [scale] (gate off only).
bool constellationBareAtScale(double scale) =>
    !kFieldSemanticZoomEnabled && scale < kConstellationBareDetailScale;

/// Detail policy for [ConstellationFrameNodeInput.labelCandidate] (R03b sets this
/// before calling [computeConstellationPresentationFrame]). Each level's
/// labels are a subset of the next closer level's.
bool constellationLabelCandidateForDetail({
  required ConstellationDetailLevel detail,
  required int priority,
  required int ring,
}) {
  switch (detail) {
    case ConstellationDetailLevel.close:
    case ConstellationDetailLevel.district:
      return true;
    case ConstellationDetailLevel.overview:
      return priority != 2 || ring <= 1;
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
    this.labelTier = 0,
  });

  final GraphNodeId id;
  final Offset centre;
  final double bodyDiameter;
  final double badgeOverhang;
  final Size labelSize;
  final int priority;
  final int ring;
  final bool labelCandidate;

  /// Orders people of the same [priority] under a tight label budget, before
  /// the [ring] does: lower tiers are named first.
  final int labelTier;
}

@immutable
final class ConstellationFrameChipInput {
  const ConstellationFrameChipInput({
    required this.authorId,
    required this.authorGraphId,
    required this.size,
    this.expanded = false,
  });

  final String authorId;
  final GraphNodeId authorGraphId;
  final Size size;

  /// The group is expanded and the chip collapses it: kept at every detail
  /// level, as it is the only way back (#459).
  final bool expanded;
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

  ConstellationPresentationFrame translated({
    required Object snapshot,
    required int cameraRevision,
    required Offset delta,
  }) {
    Map<K, Rect> shift<K>(Map<K, Rect> rects) => {
      for (final entry in rects.entries) entry.key: entry.value.shift(delta),
    };
    return ConstellationPresentationFrame(
      snapshot: snapshot,
      cameraRevision: cameraRevision,
      detail: detail,
      paintOrder: paintOrder,
      bodies: shift(bodies),
      labels: shift(labels),
      tapTargets: shift(tapTargets),
      chips: shift(chips),
      forcedLabels: forcedLabels,
    );
  }

  /// This frame with every node's rects moved onto the centre [centreOf]
  /// gives it on the camera of [cameraRevision]; sizes stay as painted.
  ConstellationPresentationFrame recentredOn({
    required int cameraRevision,
    required Offset? Function(GraphNodeId id) centreOf,
  }) {
    Map<GraphNodeId, Rect> shift(Map<GraphNodeId, Rect> rects) => {
      for (final entry in rects.entries)
        entry.key: switch ((centreOf(entry.key), bodies[entry.key])) {
          (final centre?, final body?) => entry.value.shift(
            centre - body.center,
          ),
          _ => entry.value,
        },
    };
    return ConstellationPresentationFrame(
      snapshot: snapshot,
      cameraRevision: cameraRevision,
      detail: detail,
      paintOrder: paintOrder,
      bodies: shift(bodies),
      labels: shift(labels),
      tapTargets: shift(tapTargets),
      chips: chips,
      forcedLabels: forcedLabels,
    );
  }

  /// Moves the rects of nodes (and their chips) dragged since placement.
  ConstellationPresentationFrame withDragShifts({
    required Map<GraphNodeId, Offset> nodeDeltas,
    required Map<String, Offset> chipDeltas,
  }) {
    if (nodeDeltas.isEmpty && chipDeltas.isEmpty) {
      return this;
    }
    Map<K, Rect> shift<K>(Map<K, Rect> rects, Map<K, Offset> deltas) => {
      for (final entry in rects.entries)
        entry.key: switch (deltas[entry.key]) {
          final delta? => entry.value.shift(delta),
          null => entry.value,
        },
    };
    return ConstellationPresentationFrame(
      snapshot: snapshot,
      cameraRevision: cameraRevision,
      detail: detail,
      paintOrder: paintOrder,
      bodies: shift(bodies, nodeDeltas),
      labels: shift(labels, nodeDeltas),
      tapTargets: shift(tapTargets, nodeDeltas),
      chips: shift(chips, chipDeltas),
      forcedLabels: forcedLabels,
    );
  }
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
  bool cullToViewport = true,
  bool bare = false,
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
    if (cullToViewport && !cullRect.overlaps(viewportRect)) {
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

  final occupied = _OccupiedGrid();
  for (final id in paintOrder) {
    final decorated = decoratedBodies[id];
    if (decorated != null) {
      occupied.add(decorated.inflate(1));
    }
  }

  final placedChips = <String, Rect>{};
  final sortedChips = [...chips]
    ..sort((a, b) => a.authorId.compareTo(b.authorId));

  // No overflow chip is placed, or reserved, on a bare map (#595).
  for (final chip in [
    if (!bare) ...sortedChips,
  ]) {
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
    // The author's own label slot is reserved: a chip placed first must
    // never take it (#459).
    // Forced where it is the only way to expand (closest level) or collapse
    // (expanded group) a group; otherwise a chip without a free slot is
    // omitted (#459).
    final placed =
        _firstFittingCandidate(
          candidates,
          cullToViewport ? viewportRect : null,
          occupied,
          reserved: author.labelSize.isEmpty ? null : reservedBelow.inflate(1),
        ) ??
        (detail == ConstellationDetailLevel.close || chip.expanded
            ? candidates.first
            : null);
    if (placed == null) {
      continue;
    }
    placedChips[chip.authorId] = placed;
    occupied.add(placed.inflate(1));
  }

  final labels = <GraphNodeId, Rect>{};
  final forcedLabels = <GraphNodeId>{};

  final labelNodes =
      nodesInPaintOrder
          .where((n) => !culled.contains(n.id))
          .where((n) => n.labelCandidate && n.labelSize != Size.zero)
          .toList()
        ..sort((a, b) {
          final pc = a.priority.compareTo(b.priority);
          if (pc != 0) return pc;
          final tc = a.labelTier.compareTo(b.labelTier);
          if (tc != 0) return tc;
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
    final placed = _firstFittingCandidate(
      candidates,
      cullToViewport ? viewportRect : null,
      occupied,
    );
    if (placed != null) {
      labels[node.id] = placed;
      occupied.add(placed.inflate(1));
    } else if (node.priority <= 1 && detail == ConstellationDetailLevel.close) {
      // Forced only at full detail: a zoomed-out label that does not fit
      // would sit on its neighbours (#595).
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

Rect _symmetricMinTargetRect(Rect body, double minTarget) {
  final halfW = math.max(body.width / 2, minTarget / 2);
  final halfH = math.max(body.height / 2, minTarget / 2);
  return Rect.fromCenter(
    center: body.center,
    width: halfW * 2,
    height: halfH * 2,
  );
}

/// Number of label/chip placement searches run; lets tests assert pan reuse.
@visibleForTesting
int constellationPlacementCount = 0;

Rect? _firstFittingCandidate(
  List<Rect> candidates,
  Rect? viewport,
  _OccupiedGrid occupied, {
  Rect? reserved,
}) {
  constellationPlacementCount++;
  for (final candidate in candidates) {
    if (viewport != null && !_rectFullyInside(candidate, viewport)) continue;
    if (reserved != null && candidate.overlaps(reserved)) continue;
    if (!occupied.intersects(candidate)) {
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

/// Screen-space collision broad phase; cell size does not affect placement.
final class _OccupiedGrid {
  static const _cellSize = 64.0;
  final _cells = <(int, int), List<Rect>>{};

  Iterable<(int, int)> _keys(Rect rect) sync* {
    for (
      var x = (rect.left / _cellSize).floor();
      x <= (rect.right / _cellSize).floor();
      x++
    ) {
      for (
        var y = (rect.top / _cellSize).floor();
        y <= (rect.bottom / _cellSize).floor();
        y++
      ) {
        yield (x, y);
      }
    }
  }

  void add(Rect rect) {
    for (final key in _keys(rect)) {
      (_cells[key] ??= []).add(rect);
    }
  }

  bool intersects(Rect rect) {
    for (final key in _keys(rect)) {
      for (final other in _cells[key] ?? const <Rect>[]) {
        if (rect.overlaps(other)) return true;
      }
    }
    return false;
  }
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

Rect _labelRectStart(
  Rect body,
  Size labelSize,
  double gap, {
  required bool rtl,
}) {
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
