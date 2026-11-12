import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

/// A local post-layout layer. Baseline priors keep refreshes from adding the
/// same offset repeatedly to already tidied positions.
@immutable
class ConstellationOffsetLayout implements SceneLayoutAlgorithm {
  ConstellationOffsetLayout(
    this.base,
    Map<String, ScenePoint> offsets,
    Map<String, ScenePoint> priors,
  ) : offsets = Map.unmodifiable(offsets),
      priors = Map.unmodifiable(priors);

  final SceneLayoutAlgorithm base;
  final Map<String, ScenePoint> offsets;
  final Map<String, ScenePoint> priors;

  static const _pointsEquality = MapEquality<String, ScenePoint>();

  // GraphView compares algorithms on rebuild to decide whether to lay out.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConstellationOffsetLayout &&
          runtimeType == other.runtimeType &&
          base == other.base &&
          _pointsEquality.equals(offsets, other.offsets) &&
          _pointsEquality.equals(priors, other.priors);

  @override
  int get hashCode => Object.hash(
    runtimeType,
    base,
    _pointsEquality.hash(offsets),
    _pointsEquality.hash(priors),
  );

  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) async* {
    final previous = request.previous;
    final clean = GraphLayoutRequest(
      ticket: request.ticket,
      canvasSize: request.canvasSize,
      nodesById: request.nodesById,
      edgesById: request.edgesById,
      previous: previous == null
          ? null
          : SceneLayout(
              ticket: previous.ticket,
              revision: previous.revision,
              positions: {...previous.positions, ...priors},
            ),
    );
    await for (final frame in base.layout(clean)) {
      yield GraphLayoutFrame(
        ticket: frame.ticket,
        sequence: frame.sequence,
        isTerminal: frame.isTerminal,
        positions: {
          for (final e in frame.positions.entries)
            e.key: ScenePoint(
              x: e.value.x + (offsets[e.key]?.x ?? 0),
              y: e.value.y + (offsets[e.key]?.y ?? 0),
            ),
        },
      );
    }
  }
}

/// Returns a preview to the exact positions displayed before it opened.
class ConstellationFixedLayout implements SceneLayoutAlgorithm {
  const ConstellationFixedLayout(this.positions, {this.fillMissingWith});
  final Map<String, ScenePoint> positions;
  final SceneLayoutAlgorithm Function()? fillMissingWith;

  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) async* {
    final resolveBase = fillMissingWith;
    if (resolveBase != null &&
        request.nodeIds.any((id) => !positions.containsKey(id))) {
      // Seed the base layout with the saved positions so it seats the
      // missing nodes around them instead of ignoring where they are pinned.
      final previous = request.previous;
      final seeded = GraphLayoutRequest(
        ticket: request.ticket,
        canvasSize: request.canvasSize,
        nodesById: request.nodesById,
        edgesById: request.edgesById,
        previous: SceneLayout(
          ticket: previous?.ticket ?? request.ticket,
          revision: previous?.revision ?? 0,
          positions: {
            ...?previous?.positions,
            for (final id in request.nodeIds) id: ?positions[id],
          },
        ),
      );
      await for (final frame in resolveBase().layout(seeded)) {
        yield GraphLayoutFrame(
          ticket: frame.ticket,
          sequence: frame.sequence,
          isTerminal: frame.isTerminal,
          positions: _seatBesideNeighbours(request, {
            ...frame.positions,
            for (final id in request.nodeIds) id: ?positions[id],
          }),
        );
      }
      return;
    }
    yield GraphLayoutFrame(
      ticket: request.ticket,
      sequence: 0,
      isTerminal: true,
      positions: {
        for (final id in request.nodeIds) id: ?positions[id],
      },
    );
  }

  /// Moves each unsaved node next to a neighbour that is already placed (the
  /// saved nodes first, then nodes seated here), on the nearest free spot, so
  /// a person known only from an edge sits beside whoever it came from.
  Map<String, ScenePoint> _seatBesideNeighbours(
    GraphLayoutRequest request,
    Map<String, ScenePoint> framed,
  ) {
    final result = {...framed};
    final placed = {
      for (final id in request.nodeIds)
        if (positions.containsKey(id)) id,
    };
    final neighbours = <String, Set<String>>{};
    for (final edge in request.edgesById.values) {
      neighbours.putIfAbsent(edge.sourceId, () => {}).add(edge.destinationId);
      neighbours.putIfAbsent(edge.destinationId, () => {}).add(edge.sourceId);
    }
    Rect body(String id, ScenePoint at) {
      final size = request.nodesById[id]!.size;
      return Rect.fromCenter(
        center: Offset(at.x, at.y),
        width: size.width,
        height: size.height,
      );
    }

    var progressed = true;
    while (progressed) {
      progressed = false;
      for (final id in request.nodeIds) {
        if (placed.contains(id)) continue;
        final anchorId = neighbours[id]?.firstWhereOrNull(placed.contains);
        if (anchorId == null) continue;
        final anchor = result[anchorId]!;
        final mine = request.nodesById[id]!.size;
        final theirs = request.nodesById[anchorId]!.size;
        final gap = (mine.width + theirs.width) / 2 + _seatGap;
        final others = [
          for (final other in placed)
            if (other != id) body(other, result[other]!),
        ];
        ScenePoint? seat;
        for (var ring = 1; seat == null && ring <= _seatRings; ring++) {
          for (var step = 0; seat == null && step < _seatSteps; step++) {
            final angle = 2 * math.pi * step / _seatSteps;
            final candidate = ScenePoint(
              x: anchor.x + ring * gap * math.cos(angle),
              y: anchor.y + ring * gap * math.sin(angle),
            );
            final rect = body(id, candidate);
            if (!others.any((o) => o.overlaps(rect))) seat = candidate;
          }
        }
        if (seat != null) result[id] = seat;
        placed.add(id);
        progressed = true;
      }
    }
    return result;
  }

  static const _seatGap = 16.0;
  static const _seatRings = 8;
  static const _seatSteps = 12;
}
