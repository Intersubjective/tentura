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
  const ConstellationFixedLayout(this.positions);
  final Map<String, ScenePoint> positions;

  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) async* {
    yield GraphLayoutFrame(
      ticket: request.ticket,
      sequence: 0,
      isTerminal: true,
      positions: {
        for (final id in request.nodeIds) id: ?positions[id],
      },
    );
  }
}
