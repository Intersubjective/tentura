import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:tentura/domain/port/clock_port.dart';
import 'package:tentura/domain/port/wake_up_port.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:uuid/uuid.dart';

import '../entity/placement_outbox.dart';
import '../port/constellation_anchor_repository_port.dart';
import 'constellation_field_store_case.dart';

/// Account-owned placement writes, separate from the store's read lifecycle.
@Order(2)
@singleton
final class ConstellationPlacementCase extends UseCaseBase {
  ConstellationPlacementCase(
    this._repository,
    this._store,
    this._clock,
    // Reserved for the retry scheduler in the next placement unit.
    WakeUpPort _, {
    required super.env,
    required super.logger,
  }) : _state = PlacementOutboxState(
         targets: const {},
         hasUserPlacements: false,
         generation: _store.current.generation,
       );

  static const _batchCap = 64;
  static const _uuid = Uuid();

  final ConstellationAnchorRepositoryPort _repository;
  final ConstellationFieldStoreCase _store;
  final ClockPort _clock;
  final _changes = StreamController<PlacementOutboxState>.broadcast();
  PlacementOutboxState _state;
  bool _flushing = false;
  bool _disposed = false;

  PlacementOutboxState get current => _state;
  Stream<PlacementOutboxState> get changes => _changes.stream;

  void place({
    required ConstellationAnchorTarget parent,
    required ConstellationAnchorPosition position,
    required Iterable<
      ({
        ConstellationAnchorTarget target,
        ConstellationAnchorPosition position,
      })
    >
    companions,
  }) {
    final positions = {parent: position};
    for (final companion in companions) {
      positions[companion.target] = companion.position;
    }
    if (positions.length > _batchCap) {
      throw ArgumentError.value(positions.length, 'cluster size', 'Maximum 64');
    }
    final clusterId = _uuid.v4();
    _enqueue([
      for (final entry in positions.entries)
        PlacementOp.upsert(
          clientOpId: _uuid.v4(),
          clusterId: clusterId,
          target: entry.key,
          position: entry.value,
        ),
    ]);
  }

  void unpin(ConstellationAnchorTarget target) {
    _enqueue([
      PlacementOp.delete(
        clientOpId: _uuid.v4(),
        clusterId: _uuid.v4(),
        target: target,
      ),
    ]);
  }

  void _enqueue(List<PlacementOp> ops) {
    if (_disposed) return;
    final targets = Map.of(_state.targets);
    for (final op in ops) {
      final target = targets[op.target] ?? const PlacementTargetState();
      targets[op.target] = target.copyWith(
        latestPending: PlacementSlot(
          op: op,
          status: PlacementSlotStatus.queued,
        ),
      );
    }
    _emit(_state.copyWith(targets: targets, hasUserPlacements: true));
    if (!_flushing) {
      _flushing = true;
      // Coalesce synchronous inputs without a real-time timer.
      scheduleMicrotask(() => unawaited(_flush()));
    }
  }

  List<PlacementSlot> _nextBatch() {
    final clusters = <String, List<PlacementSlot>>{};
    for (final target in _state.targets.values) {
      final slot = target.latestPending;
      if (slot?.status == PlacementSlotStatus.queued) {
        clusters.putIfAbsent(slot!.op.clusterId, () => []).add(slot);
      }
    }
    final batch = <PlacementSlot>[];
    for (final cluster in clusters.values) {
      if (cluster.any(
        (slot) => _state.targets[slot.op.target]!.inFlight != null,
      )) {
        continue;
      }
      if (batch.length + cluster.length > _batchCap) break;
      batch.addAll(cluster);
    }
    return batch;
  }

  Future<void> _flush() async {
    try {
      while (!_disposed) {
        final batch = _nextBatch();
        if (batch.isEmpty) return;
        final params = _store.projectionParams;
        final targets = Map.of(_state.targets);
        final confirmed = {
          for (final anchor
              in _store.current.field?.resolvedAnchorProjection.anchors ??
                  <ConstellationAnchor>[])
            anchor.target: anchor,
        };
        final now = _clock.now();
        for (final slot in batch) {
          targets[slot.op.target] = targets[slot.op.target]!.copyWith(
            latestPending: null,
            inFlight: slot.copyWith(
              status: PlacementSlotStatus.inFlight,
              attempts: slot.attempts + 1,
              preOpConfirmed: confirmed[slot.op.target],
              inFlightSince: now,
            ),
          );
        }
        _emit(_state.copyWith(targets: targets));
        try {
          final result = await _repository.apply(
            ops: [for (final slot in batch) _applyOp(slot.op)],
            params: params.membershipFilters,
          );
          if (_disposed) return;
          _store.settle(result, () => _settleSlots(result), params: params);
        } on Object catch (error, stackTrace) {
          if (_disposed) return;
          // A transport failure cannot prove that the write was rejected.
          final unknown = Map.of(_state.targets);
          for (final slot in batch) {
            final target = unknown[slot.op.target]!;
            unknown[slot.op.target] = target.copyWith(
              inFlight: target.inFlight!.copyWith(
                status: PlacementSlotStatus.commitUnknown,
              ),
            );
          }
          _emit(_state.copyWith(targets: unknown));
          logger.warning(
            'Constellation placement apply failed',
            error,
            stackTrace,
          );
        }
      }
    } finally {
      _flushing = false;
    }
  }

  ConstellationAnchorApplyOp _applyOp(PlacementOp op) =>
      ConstellationAnchorApplyOp(
        clientOpId: op.clientOpId,
        kind: op is PlacementUpsert
            ? ConstellationAnchorOpKind.upsert
            : ConstellationAnchorOpKind.delete,
        target: op.target,
        position: op is PlacementUpsert ? op.position : null,
        ifRevision: op.ifRevision,
      );

  void _settleSlots(ConstellationAnchorApplyResult result) {
    final results = {for (final op in result.results) op.clientOpId: op};
    final targets = Map.of(_state.targets);
    for (final entry in _state.targets.entries) {
      final target = entry.value;
      final slot = target.inFlight;
      final outcome = results[slot?.op.clientOpId];
      if (slot == null || outcome == null) continue;
      final pending =
          target.latestPending ??
          (outcome.status == ConstellationAnchorOpStatus.rejected
              ? slot.copyWith(
                  status: PlacementSlotStatus.rejected,
                  reasonCode: outcome.reason,
                )
              : null);
      if (pending == null) {
        targets.remove(entry.key);
      } else {
        targets[entry.key] = target.copyWith(
          inFlight: null,
          latestPending: pending,
        );
      }
    }
    _emit(_state.copyWith(targets: targets));
  }

  void _emit(PlacementOutboxState state) {
    _state = state;
    _changes.add(state);
  }

  Future<void> dispose() async {
    _disposed = true;
    await _changes.close();
  }
}
