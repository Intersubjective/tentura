import 'dart:collection';

import '../constellation_layout.dart';
import 'spatial_index.dart';

typedef LayoutInput = ConstellationPlacedLayoutInput;

/// Checkpoints per unit: small enough to stay far below 0.5 ms at N=1000,
/// large enough that a full job is not millions of units.
const _checkpointsPerUnit = 8;

/// Published geometry and the dependencies used to compute it.
final class LayoutResult {
  LayoutResult._(ConstellationLayout layout, this._input)
    : positions = UnmodifiableMapView(layout.positions),
      ring = UnmodifiableMapView(layout.ring);

  final Map<String, ConstellationPoint> positions;
  final Map<String, int> ring;
  final LayoutInput _input;
}

abstract interface class LayoutJob {
  /// Runs at most [units] units, each a fixed batch of checkpoints. Zero or
  /// negative units do no work.
  bool step(int units);

  /// Available only after completion; discarding an unfinished job publishes
  /// nothing and never mutates the previous result.
  LayoutResult get result;
}

/// Pure, deterministic layout with deferred planning and bounded work units.
final class ConstellationLayoutEngine {
  ConstellationLayoutEngine({required this._newIndex});

  final SpatialIndex Function() _newIndex;

  LayoutJob start(LayoutResult? previous, LayoutInput next) =>
      _ConstellationLayoutJob(previous, next, _newIndex);
}

final class _ConstellationLayoutJob implements LayoutJob {
  _ConstellationLayoutJob(this._previous, this._next, this._newIndex);

  final LayoutResult? _previous;
  final LayoutInput _next;
  final SpatialIndex Function() _newIndex;
  late final Iterator<void> _steps = _run().iterator;
  late final LayoutResult _result;
  bool _done = false;

  @override
  LayoutResult get result {
    if (!_done) throw StateError('Layout job has not finished');
    return _result;
  }

  @override
  bool step(int units) {
    if (_done) return true;
    for (var unit = 0; unit < units; unit++) {
      for (var i = 0; i < _checkpointsPerUnit; i++) {
        if (!_steps.moveNext()) {
          _done = true;
          return true;
        }
      }
    }
    return false;
  }

  Iterable<void> _run() sync* {
    final previous = _previous;
    var input = _next;
    Set<String>? unchanged;
    if (previous != null) {
      final before = previous._input;
      final beforeAuthors = <String, String>{};
      final nextAuthors = <String, String>{};
      yield* _resolveAuthors(before, beforeAuthors);
      yield* _resolveAuthors(input, nextAuthors);
      unchanged = <String>{};
      final sameField =
          before.egoId == input.egoId &&
          before.spacing == input.spacing &&
          before.maxHops == input.maxHops &&
          before.viewportClass == input.viewportClass;
      for (final id in input.nodeSizes.keys) {
        if (sameField &&
            before.nodeSizes[id] == input.nodeSizes[id] &&
            before.footprints[id] == input.footprints[id] &&
            before.paths.depth[id] == input.paths.depth[id] &&
            before.paths.derived[id] == input.paths.derived[id] &&
            before.paths.parent[id] == input.paths.parent[id] &&
            before.paths.parentTier[id] == input.paths.parentTier[id] &&
            before.paths.keep.contains(id) == input.paths.keep.contains(id) &&
            before.paths.ring.contains(id) == input.paths.ring.contains(id) &&
            before.paths.attributed.contains(id) ==
                input.paths.attributed.contains(id) &&
            before.supportPersonIds.contains(id) ==
                input.supportPersonIds.contains(id) &&
            before.automaticKeptPeerIds.contains(id) ==
                input.automaticKeptPeerIds.contains(id) &&
            before.pinnedPersonIds.contains(id) ==
                input.pinnedPersonIds.contains(id) &&
            before.pinnedRequestIds.contains(id) ==
                input.pinnedRequestIds.contains(id) &&
            beforeAuthors[id] == nextAuthors[id]) {
          unchanged.add(id);
        }
        yield null;
      }
      input = (
        egoId: input.egoId,
        paths: input.paths,
        automaticKeptPeerIds: input.automaticKeptPeerIds,
        pinnedPersonIds: input.pinnedPersonIds,
        pinnedRequestIds: input.pinnedRequestIds,
        supportPersonIds: input.supportPersonIds,
        anchorByNodeId: input.anchorByNodeId,
        priorHints: (
          positions: previous.positions,
          ring: previous.ring,
          viewportClass: before.viewportClass,
        ),
        nodeSizes: input.nodeSizes,
        satelliteRequestIdsByAuthor: input.satelliteRequestIdsByAuthor,
        requestAuthorById: input.requestAuthorById,
        egoOwnRequestIds: input.egoOwnRequestIds,
        spacing: input.spacing,
        maxHops: input.maxHops,
        viewportClass: input.viewportClass,
        footprints: input.footprints,
      );
      yield null;
    }
    yield* constellationPlacedLayoutSteps(
      input: input,
      newIndex: _newIndex,
      unchangedNodeIds: unchanged,
      onComplete: (layout) => _result = LayoutResult._(layout, _next),
    );
  }
}

Iterable<void> _resolveAuthors(
  LayoutInput input,
  Map<String, String> authors,
) sync* {
  for (final entry in input.satelliteRequestIdsByAuthor.entries) {
    for (final id in entry.value) {
      authors.putIfAbsent(id, () => entry.key);
      yield null;
    }
  }
  for (final entry in input.requestAuthorById.entries) {
    authors[entry.key] = entry.value;
    yield null;
  }
  for (final id in input.egoOwnRequestIds) {
    authors[id] = input.egoId;
    yield null;
  }
}
