import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:force_directed_graphview/force_directed_graphview.dart';

import '../../domain/layout/constellation_magnet_layout.dart';
import '../../domain/layout/layout_geometry.dart';

/// Magnets bias free members after normal layout. Clean priors keep repeated
/// layout passes from compounding the attraction or moving unrelated people.
@immutable
class ConstellationMagnetLayout implements SceneLayoutAlgorithm {
  ConstellationMagnetLayout({
    required this.base,
    required Map<String, ScenePoint> priors,
    required Map<String, List<LPoint>> magnetsByPerson,
    required Map<String, String> followers,
  }) : priors = Map.unmodifiable(priors),
       magnetsByPerson = Map.unmodifiable({
         for (final e in magnetsByPerson.entries)
           e.key: List<LPoint>.unmodifiable(e.value),
       }),
       followers = Map.unmodifiable(followers);

  final SceneLayoutAlgorithm base;
  final Map<String, ScenePoint> priors;
  final Map<String, List<LPoint>> magnetsByPerson;
  final Map<String, String> followers;

  static const _equality = DeepCollectionEquality();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConstellationMagnetLayout &&
          base == other.base &&
          _equality.equals(priors, other.priors) &&
          _equality.equals(magnetsByPerson, other.magnetsByPerson) &&
          _equality.equals(followers, other.followers);

  @override
  int get hashCode => Object.hash(
    base,
    _equality.hash(priors),
    _equality.hash(magnetsByPerson),
    _equality.hash(followers),
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
      final positions = Map.of(frame.positions);
      for (final entry in magnetsByPerson.entries) {
        final at = frame.positions[entry.key];
        if (at == null) continue;
        final moved = attractToTagMagnets((x: at.x, y: at.y), entry.value);
        positions[entry.key] = ScenePoint(x: moved.x, y: moved.y);
      }
      for (final entry in followers.entries) {
        final at = frame.positions[entry.key];
        final was = frame.positions[entry.value];
        final now = positions[entry.value];
        if (at == null || was == null || now == null) continue;
        positions[entry.key] = ScenePoint(
          x: at.x + now.x - was.x,
          y: at.y + now.y - was.y,
        );
      }
      yield GraphLayoutFrame(
        ticket: frame.ticket,
        sequence: frame.sequence,
        isTerminal: frame.isTerminal,
        positions: positions,
      );
    }
  }
}
