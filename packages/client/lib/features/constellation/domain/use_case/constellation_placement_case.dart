import 'dart:async';
import 'dart:math';

import 'package:injectable/injectable.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/domain/port/clock_port.dart';
import 'package:tentura/domain/port/wake_up_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:uuid/uuid.dart';

import '../entity/constellation_field.dart';
import '../entity/constellation_layout_snapshot.dart';
import '../entity/placement_outbox.dart';
import '../placement_overlay.dart';
import '../port/constellation_anchor_repository_port.dart';
import 'constellation_arrangement_history.dart';
import 'constellation_field_store_case.dart';

/// Most placements one [ConstellationPlacementCase.place] call (one cluster,
/// sent as one batch) may hold.
const int kConstellationPlacementBatchCap = 400;

/// Account-owned placement writes, separate from the store's read lifecycle.
@Order(2)
@singleton
final class ConstellationPlacementCase extends UseCaseBase {
  ConstellationPlacementCase(
    this._repository,
    this._store,
    this._clock,
    this._wakeUp, {
    required RealtimeSyncCase realtime,
    @ignoreParam this.recordAutomaticHistory = kFieldArrangeV2Enabled,
    required super.env,
    required super.logger,
  }) : _state = PlacementOutboxState(
         targets: const {},
         hasUserPlacements: false,
         generation: _store.current.generation,
       ) {
    _subscriptions = [
      _store.changes.listen((_) => _syncGeneration()),
      realtime.catchUps.listen((_) => _onCatchUp()),
    ];
    _store.holdCatchUpReads(() => _replayBarrier?.future);
    _store.holdAnchorHints(() => _applyBarrier?.future);
  }

  static const _batchCap = kConstellationPlacementBatchCap;
  static const _maxAttempts = 3;
  static const _baseBackoff = Duration(seconds: 1);
  static const _maxBackoff = Duration(seconds: 30);
  static const _maxReplayJitter = Duration(seconds: 5);
  static const _uuid = Uuid();

  final bool recordAutomaticHistory;
  final ConstellationAnchorRepositoryPort _repository;
  final ConstellationFieldStoreCase _store;
  final ClockPort _clock;
  final WakeUpPort _wakeUp;
  final _random = Random();
  late final List<StreamSubscription<Object?>> _subscriptions;
  final _changes = StreamController<PlacementOutboxState>.broadcast();
  final _notices = StreamController<LazyWriteNotice>.broadcast();
  PlacementOutboxState _state;

  /// One timer per first dispatch; a retry never adds one.
  final _overdueHandles = <WakeUpHandle>{};
  var _noticeRaised = false;
  bool _flushing = false;
  bool _disposed = false;

  /// Identifies the live flush loop; a reset or a newer loop replaces it.
  Object? _loopToken;

  /// Unknown writes whose backoff or replay wake-up has fired.
  final _dueIds = <String>{};
  WakeUpHandle? _retryHandle;
  bool _replayScheduled = false;

  /// Held by the store so a catch-up read follows the replay's dispatch.
  Completer<void>? _replayBarrier;

  /// Held by the store so a realtime anchor hint is judged only after the
  /// apply batch in flight (whose echo may beat its acknowledgement) settles.
  Completer<void>? _applyBarrier;

  /// Screen-session undo / redo of drags, unpins and resets.
  late final history = ConstellationArrangementHistory(
    applyOps: _applyHistoryOps,
    restoreSnapshot: _restoreSnapshot,
    applyLocalLayout: (_) async {},
    flushPlacementOutbox: flushPendingPlacements,
    saveSnapshot: _saveSnapshot,
    newOpId: _uuid.v4,
    restoreFavourite: (id) =>
        _snapshots.restoreFavourite(snapshotId: id, clientOpId: _uuid.v4()),
  );

  ConstellationLayoutSnapshotRepositoryPort get _snapshots =>
      _repository as ConstellationLayoutSnapshotRepositoryPort;

  Future<List<ConstellationLayoutSnapshot>> listLayoutSnapshots() =>
      _snapshots.listLayoutSnapshots();

  Future<void> saveFavourite() async {
    await flushPendingPlacements();
    final previous = (await listLayoutSnapshots())
        .where((s) => s.kind == 0)
        .firstOrNull;
    final saved = await _snapshots.saveFavourite(clientOpId: _uuid.v4());
    history.record(
      FavouriteSnapshotEntry(beforeId: previous?.id ?? '', afterId: saved),
    );
  }

  Future<bool> restoreLayoutSnapshot(String id) async {
    await flushPendingPlacements();
    final inverse = await _restoreSnapshot(id);
    if (inverse == null) return false;
    history.record(SnapshotRestoreEntry(snapshotId: inverse));
    return true;
  }

  /// Await the actual acknowledgements, including queued writes coalesced in
  /// this turn. Unknown outcomes cannot be captured safely by a bulk action.
  Future<void> flushPendingPlacements() async {
    while (_flushing) {
      await _flushCompletion?.future;
    }
    if (_state.targets.values.any(
      (t) =>
          t.inFlight != null ||
          t.latestPending?.status == PlacementSlotStatus.queued,
    )) {
      throw StateError('Placements have not been acknowledged');
    }
  }

  Completer<void>? _flushCompletion;
  DateTime? _lastManualSnapshotAt;
  bool _manualSnapshotDue = false;

  Future<bool> undo() => history.undo();
  Future<bool> redo() => history.redo();

  /// Outcome (true = accepted) of each in-flight write, by client op id.
  final _outcomes = <String, Completer<bool>>{};

  Future<bool> _watch(Iterable<PlacementOp> ops) async {
    final watchers = [
      for (final op in ops)
        (_outcomes[op.clientOpId] = Completer<bool>()).future,
    ];
    return (await Future.wait(watchers)).every((ok) => ok);
  }

  /// Undo / redo writes go through the same outbox as the original drag.
  Future<bool> _applyHistoryOps(List<ConstellationAnchorApplyOp> ops) {
    final clusterId = _uuid.v4();
    final placementOps = [
      for (final op in ops)
        switch (op.kind) {
          ConstellationAnchorOpKind.upsert => PlacementOp.upsert(
            clientOpId: op.clientOpId,
            clusterId: clusterId,
            target: op.target,
            position: op.position!,
            baseRevision: _baseRevision,
          ),
          ConstellationAnchorOpKind.delete => PlacementOp.delete(
            clientOpId: op.clientOpId,
            clusterId: clusterId,
            target: op.target,
            baseRevision: _baseRevision,
          ),
        },
    ];
    final outcome = _watch(placementOps);
    _enqueue(placementOps);
    return outcome;
  }

  /// The layout about to be replaced, saved as a history snapshot of [reason].
  Future<String> _saveSnapshot(String reason) =>
      _repository.saveLayoutSnapshot(reason: reason, clientOpId: _uuid.v4());

  /// Undo / redo of a reset or restore: the server puts the saved layout back
  /// in one step; the id of the layout it replaced undoes it, null when the
  /// server refused.
  Future<String?> _restoreSnapshot(String snapshotId) async {
    final applying = _applyBarrier;
    if (applying != null) await applying.future;
    try {
      return _repository.restoreLayoutSnapshot(
        snapshotId: snapshotId,
        clientOpId: _uuid.v4(),
      );
    } on Object catch (error, stackTrace) {
      logger.warning('Constellation layout restore failed', error, stackTrace);
      return null;
    }
  }

  /// Records [ops] as one history step and marks it failed if any is rejected.
  void _record(
    Map<ConstellationAnchorTarget, ConstellationAnchorPosition?> after,
    List<PlacementOp> ops,
  ) {
    final confirmed = {
      for (final anchor
          in _store.current.field?.resolvedAnchorProjection.anchors ??
              <ConstellationAnchor>[])
        anchor.target: anchor.position,
    };
    final handle = history.record(
      AnchorBatchEntry.placement(
        changes: {
          for (final entry in after.entries)
            entry.key: (before: confirmed[entry.key], after: entry.value),
        },
        newOpId: _uuid.v4,
      ),
    );
    unawaited(
      _watch(ops).then((ok) {
        if (!ok) history.markFailed(handle);
      }),
    );
  }

  PlacementOutboxState get current => _state;
  Stream<PlacementOutboxState> get changes => _changes.stream;

  /// One event per overdue-acknowledgement episode (ARCH 5.9).
  Stream<LazyWriteNotice> get lazyWriteNotices => _notices.stream;

  /// Writes the user should be told about, as of the case's own clock.
  ({Map<ConstellationAnchorTarget, PlacementCue> cues, Duration? nextChange})
  get cues => placementCues(_state, now: _clock.now());

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
    bool saveManualHistory = true,
    ConstellationPerson? grabbedPerson,
    ConstellationRequest? grabbedRequest,
  }) {
    final positions = {parent: position};
    for (final companion in companions) {
      positions[companion.target] = companion.position;
    }
    final field = _store.current.field;
    final projection = field?.resolvedAnchorProjection;
    final people = {
      for (final p in [
        ...?field?.peers,
        ...?projection?.pinnedPeers,
        ...?projection?.supportPeers,
      ])
        p.id: p,
    };
    final requests = {
      for (final r in [
        ...?field?.requests,
        ...?projection?.pinnedRequests,
      ])
        r.id: r,
    };
    if (positions.length > _batchCap) {
      throw ArgumentError.value(
        positions.length,
        'cluster size',
        'Maximum $_batchCap',
      );
    }
    final clusterId = _uuid.v4();
    final ops = [
      for (final entry in positions.entries)
        PlacementOp.upsert(
          clientOpId: _uuid.v4(),
          clusterId: clusterId,
          target: entry.key,
          position: entry.value,
          baseRevision: _baseRevision,
          capturedPerson: entry.key.kind == ConstellationAnchorTargetKind.person
              ? (entry.key == parent ? grabbedPerson : null) ??
                    people[entry.key.id]
              : null,
          capturedRequest:
              entry.key.kind == ConstellationAnchorTargetKind.beacon
              ? (entry.key == parent ? grabbedRequest : null) ??
                    requests[entry.key.id]
              : null,
        ),
    ];
    _record(positions, ops);
    _manualSnapshotDue |= saveManualHistory && recordAutomaticHistory;
    _enqueue(ops);
  }

  void unpin(ConstellationAnchorTarget target) {
    final op = PlacementOp.delete(
      clientOpId: _uuid.v4(),
      clusterId: _uuid.v4(),
      target: target,
      baseRevision: _baseRevision,
    );
    _record({target: null}, [op]);
    _enqueue([op]);
  }

  /// The account anchor revision the user is looking at; a write based on
  /// one older than a reset is refused by the server (#251).
  ConstellationAnchorRevision? get _baseRevision =>
      _store.current.field?.resolvedAnchorProjection.revision;

  /// True while [resetAll] runs: nothing is sent until it settles.
  bool _resetting = false;

  /// «Сбросить позиции» (#251): removes every user-placed position of the
  /// account, hidden and off-screen ones included.
  ///
  /// Every write made so far predates the reset and is dropped at once: the
  /// reset removes whatever of them committed, and the server refuses any
  /// that still arrives, since each is based on a pre-reset revision. A batch
  /// already sent settles before the reset is sent, so its acknowledgement
  /// cannot reach the server or the store after it. Placements made while
  /// the reset runs are kept and sent after it, based on the reset revision.
  /// The reset is retried under one operation id, so a retry never resets
  /// twice; concurrent calls share one reset; a change of account abandons
  /// it before anything more is sent. With [saveHistory] the server saves the
  /// cleared layout in the same call and the reset becomes one undoable
  /// history entry.
  Future<ConstellationAnchorResetResult> resetAll({bool saveHistory = false}) =>
      _resetInFlight ??= _resetAll(
        saveHistory: saveHistory,
      ).whenComplete(() => _resetInFlight = null);

  Future<ConstellationAnchorResetResult>? _resetInFlight;

  Future<ConstellationAnchorResetResult> _resetAll({
    required bool saveHistory,
  }) async {
    if (_disposed) {
      throw StateError('The placement case is disposed');
    }
    _syncGeneration();
    final generation = _state.generation;
    _resetting = true;
    // The loop stops at its next check; an apply in flight finishes first.
    _loopToken = null;
    _flushing = false;
    final applying = _applyBarrier;
    _dropAllWrites();
    try {
      if (applying != null) await applying.future;
      final clientOpId = _uuid.v4();
      for (var attempt = 1; ; attempt++) {
        _requireAccount(generation);
        try {
          final result = await _repository.reset(
            clientOpId: clientOpId,
            saveHistory: saveHistory,
          );
          if (!_disposed && _store.current.generation == generation) {
            _store.applyReset(result.afterRevision);
            if (saveHistory) {
              history.record(
                const SnapshotRestoreEntry(snapshotId: kLatestLayoutSnapshotId),
              );
            }
          }
          return result;
        } on Object catch (error, stackTrace) {
          if (_disposed ||
              attempt >= _maxAttempts ||
              _store.current.generation != generation) {
            rethrow;
          }
          logger.warning('Constellation reset failed', error, stackTrace);
        }
      }
    } finally {
      _resetting = false;
      if (!_disposed) {
        _syncGeneration();
        _rebaseQueuedWrites();
        _kick();
      }
    }
  }

  /// A reset belongs to the account that asked for it.
  void _requireAccount(int generation) {
    if (_disposed || _store.current.generation != generation) {
      throw StateError('The account changed before the reset was sent');
    }
  }

  void _failOutcomes() {
    final pending = _outcomes.values.toList();
    _outcomes.clear();
    for (final outcome in pending) {
      outcome.complete(false);
    }
  }

  void _dropAllWrites() {
    _failOutcomes();
    _retryHandle?.cancel();
    _retryHandle = null;
    _replayScheduled = false;
    _dueIds.clear();
    _cancelOverdue();
    _replayBarrier?.complete();
    _replayBarrier = null;
    _emit(
      PlacementOutboxState(
        targets: const {},
        hasUserPlacements: false,
        generation: _state.generation,
      ),
    );
  }

  /// Writes the user made while the reset ran come after it.
  void _rebaseQueuedWrites() {
    final base = _baseRevision;
    if (base == null || _state.targets.isEmpty) return;
    _emit(
      _state.copyWith(
        targets: {
          for (final entry in _state.targets.entries)
            entry.key: switch (entry.value.latestPending) {
              final PlacementSlot slot
                  when slot.status == PlacementSlotStatus.queued =>
                entry.value.copyWith(
                  latestPending: slot.copyWith(
                    op: switch (slot.op) {
                      final PlacementUpsert op => op.copyWith(
                        baseRevision: base,
                      ),
                      final PlacementDelete op => op.copyWith(
                        baseRevision: base,
                      ),
                    },
                  ),
                ),
              _ => entry.value,
            },
        },
      ),
    );
  }

  /// A rejection is resent as a new write; an unknown outcome replays its id.
  void retry(ConstellationAnchorTarget target) {
    if (_disposed) return;
    _syncGeneration();
    final state = _state.targets[target];
    final pending = state?.latestPending;
    if (pending != null && pending.status == PlacementSlotStatus.rejected) {
      final op = pending.op;
      // A fresh write, based on the revision the user sees now (#251).
      final fresh = switch (op) {
        PlacementUpsert() => op.copyWith(
          clientOpId: _uuid.v4(),
          clusterId: _uuid.v4(),
          baseRevision: _baseRevision,
        ),
        PlacementDelete() => op.copyWith(
          clientOpId: _uuid.v4(),
          clusterId: _uuid.v4(),
          baseRevision: _baseRevision,
        ),
      };
      _emit(
        _state.copyWith(
          targets: {
            ..._state.targets,
            target: state!.copyWith(
              latestPending: PlacementSlot(
                op: fresh,
                status: PlacementSlotStatus.queued,
              ),
            ),
          },
        ),
      );
      _kick();
      return;
    }
    final unknown = state?.inFlight;
    if (unknown?.status == PlacementSlotStatus.commitUnknown) {
      _dueIds.add(unknown!.op.clientOpId);
      _kick();
    }
  }

  /// Drops an unsent or rejected write; unresolved writes settle before undoing.
  void discard(ConstellationAnchorTarget target) {
    if (_disposed) return;
    _syncGeneration();
    final state = _state.targets[target];
    if (state == null) return;
    final inFlight = state.inFlight;
    final PlacementTargetState next;
    if (state.latestPending != null) {
      next = state.copyWith(latestPending: null);
    } else if (inFlight?.status == PlacementSlotStatus.inFlight ||
        inFlight?.status == PlacementSlotStatus.commitUnknown) {
      next = state.copyWith(
        inFlight: inFlight!.copyWith(discardOnSettle: true),
      );
    } else {
      return;
    }
    final targets = Map.of(_state.targets);
    if (next.inFlight == null && next.latestPending == null) {
      targets.remove(target);
    } else {
      targets[target] = next;
    }
    _emit(_state.copyWith(targets: targets));
    if (inFlight?.status == PlacementSlotStatus.commitUnknown &&
        next.inFlight?.discardOnSettle == true) {
      _dueIds.add(inFlight!.op.clientOpId);
      _kick();
    }
  }

  void _enqueue(List<PlacementOp> ops) {
    if (_disposed) return;
    _syncGeneration();
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
    _kick();
  }

  void _kick() {
    if (_flushing || _resetting) return;
    _flushing = true;
    _flushCompletion = Completer<void>();
    final token = _loopToken = Object();
    // Coalesce synchronous inputs without a real-time timer.
    scheduleMicrotask(() => unawaited(_flush(token)));
  }

  /// Unknown writes that are due for a replay, then queued writes.
  ({List<PlacementSlot> slots, bool retry}) _nextBatch() {
    final unknown = <String, List<PlacementSlot>>{};
    final unknownIds = <String>{};
    for (final target in _state.targets.values) {
      final slot = target.inFlight;
      if (slot?.status != PlacementSlotStatus.commitUnknown) continue;
      unknownIds.add(slot!.op.clientOpId);
      if (_dueIds.contains(slot.op.clientOpId)) {
        unknown.putIfAbsent(slot.op.clusterId, () => []).add(slot);
      }
    }
    _dueIds.retainAll(unknownIds);
    final retry = _fill(unknown.values, checkInFlight: false);
    if (retry.isNotEmpty) return (slots: retry, retry: true);
    final clusters = <String, List<PlacementSlot>>{};
    for (final target in _state.targets.values) {
      final slot = target.latestPending;
      if (slot?.status == PlacementSlotStatus.queued) {
        clusters.putIfAbsent(slot!.op.clusterId, () => []).add(slot);
      }
    }
    return (slots: _fill(clusters.values, checkInFlight: true), retry: false);
  }

  List<PlacementSlot> _fill(
    Iterable<List<PlacementSlot>> clusters, {
    required bool checkInFlight,
  }) {
    final batch = <PlacementSlot>[];
    for (final cluster in clusters) {
      if (checkInFlight &&
          cluster.any(
            (slot) => _state.targets[slot.op.target]!.inFlight != null,
          )) {
        continue;
      }
      if (batch.length + cluster.length > _batchCap) break;
      batch.addAll(cluster);
    }
    return batch;
  }

  bool _isLive(Object token) {
    if (_disposed) return false;
    _syncGeneration();
    return identical(token, _loopToken);
  }

  Future<void> _flush(Object token) async {
    final completed = _flushCompletion!;
    try {
      while (_isLive(token)) {
        if (_manualSnapshotDue) {
          _manualSnapshotDue = false;
          final now = _clock.now();
          if (_lastManualSnapshotAt == null ||
              now.difference(_lastManualSnapshotAt!) >=
                  const Duration(minutes: 10)) {
            try {
              await _saveSnapshot('manual');
              if (!_isLive(token)) return;
              _lastManualSnapshotAt = now;
            } on Object catch (error, stackTrace) {
              logger.warning(
                'Could not save manual layout history',
                error,
                stackTrace,
              );
            }
          }
        }

        final (slots: batch, :retry) = _nextBatch();
        if (retry) _dueIds.removeAll(batch.map((slot) => slot.op.clientOpId));
        _releaseBarrier();
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
          // A replay keeps its id, payload and pre-op baseline.
          targets[slot.op.target] = retry
              ? targets[slot.op.target]!.copyWith(
                  inFlight: slot.copyWith(
                    status: PlacementSlotStatus.inFlight,
                    attempts: slot.attempts + 1,
                    inFlightSince: now,
                  ),
                )
              : targets[slot.op.target]!.copyWith(
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
        if (!retry) {
          _watchOverdue({for (final slot in batch) slot.op.clientOpId});
        }
        final applying = _applyBarrier = Completer<void>();
        try {
          final result = await _repository.apply(
            ops: [for (final slot in batch) _applyOp(slot.op)],
            params: params.membershipFilters,
          );
          // A completion for a previous account must not reach the store.
          if (!_isLive(token)) return;
          final captured = [
            for (final slot in batch)
              if (slot.op case final PlacementUpsert op) op,
          ];
          _store.settle(
            result,
            () => _settleSlots(result),
            params: params,
            capturedPeers: [
              for (final op in captured) ?op.capturedPerson,
            ],
            capturedRequests: [
              for (final op in captured) ?op.capturedRequest,
            ],
          );
        } on Object catch (error, stackTrace) {
          if (!_isLive(token)) return;
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
          _scheduleBackoff();
          logger.warning(
            'Constellation placement apply failed',
            error,
            stackTrace,
          );
        } finally {
          if (identical(_applyBarrier, applying)) _applyBarrier = null;
          // dispose() may already have released it.
          if (!applying.isCompleted) applying.complete();
        }
      }
    } finally {
      completed.complete();
      if (identical(token, _loopToken)) {
        _loopToken = null;
        _flushing = false;
      }
    }
  }

  /// Raises one notice if any of [ids] is still unacknowledged at the timeout.
  void _watchOverdue(Set<String> ids) {
    late final WakeUpHandle handle;
    handle = _wakeUp.schedule(kLazyWriteAckTimeout, () {
      _overdueHandles.remove(handle);
      if (_disposed || _noticeRaised) return;
      final overdue = _state.targets.values.any(
        (target) => ids.contains(target.inFlight?.op.clientOpId),
      );
      if (!overdue) return;
      _noticeRaised = true;
      _notices.add(const LazyWriteNotice());
    });
    _overdueHandles.add(handle);
  }

  void _cancelOverdue() {
    for (final handle in _overdueHandles) {
      handle.cancel();
    }
    _overdueHandles.clear();
    _noticeRaised = false;
  }

  bool get _hasUnknown => _state.targets.values.any(
    (target) => target.inFlight?.status == PlacementSlotStatus.commitUnknown,
  );

  void _markDue({required bool exhausted}) {
    for (final target in _state.targets.values) {
      final slot = target.inFlight;
      if (slot?.status == PlacementSlotStatus.commitUnknown &&
          (exhausted || slot!.attempts < _maxAttempts)) {
        _dueIds.add(slot!.op.clientOpId);
      }
    }
    _kick();
  }

  /// Backoff for unknown writes that still have automatic attempts left.
  void _scheduleBackoff() {
    if (_retryHandle != null) return;
    int? attempts;
    for (final target in _state.targets.values) {
      final slot = target.inFlight;
      if (slot?.status == PlacementSlotStatus.commitUnknown &&
          slot!.attempts < _maxAttempts) {
        attempts = min(attempts ?? slot.attempts, slot.attempts);
      }
    }
    if (attempts == null) return;
    final ceiling = min(
      _maxBackoff.inMilliseconds,
      _baseBackoff.inMilliseconds * (1 << (attempts - 1)),
    );
    final half = ceiling ~/ 2;
    _retryHandle = _wakeUp.schedule(
      Duration(milliseconds: half + _random.nextInt(half) + 1),
      () {
        _retryHandle = null;
        if (!_disposed) _markDue(exhausted: false);
      },
    );
  }

  /// A catch-up replays every unknown write once, jittered; the store's
  /// recovery read waits for that dispatch. Several catch-ups share one replay.
  void _onCatchUp() {
    if (_disposed) return;
    _syncGeneration();
    if (_replayScheduled || !_hasUnknown) return;
    _retryHandle?.cancel();
    _replayScheduled = true;
    _replayBarrier ??= Completer<void>();
    _retryHandle = _wakeUp.schedule(
      Duration(
        milliseconds: _random.nextInt(_maxReplayJitter.inMilliseconds) + 1,
      ),
      () {
        _retryHandle = null;
        _replayScheduled = false;
        if (_disposed) return;
        _markDue(exhausted: true);
        _releaseBarrier();
      },
    );
  }

  void _releaseBarrier() {
    if (_replayScheduled || _dueIds.isNotEmpty) return;
    _replayBarrier?.complete();
    _replayBarrier = null;
  }

  void _syncGeneration() {
    if (_store.current.generation == _state.generation) return;
    _lastManualSnapshotAt = null;
    _manualSnapshotDue = false;
    // Another account: drop its writes, wake-ups and in-flight completions.
    _retryHandle?.cancel();
    _retryHandle = null;
    _replayScheduled = false;
    _dueIds.clear();
    _cancelOverdue();
    _failOutcomes();
    _loopToken = null;
    _flushing = false;
    _replayBarrier?.complete();
    _replayBarrier = null;
    _emit(
      PlacementOutboxState(
        targets: const {},
        hasUserPlacements: false,
        generation: _store.current.generation,
      ),
    );
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
        baseRevision: switch (op) {
          PlacementUpsert(:final baseRevision) => baseRevision,
          PlacementDelete(:final baseRevision) => baseRevision,
        },
      );

  void _settleSlots(ConstellationAnchorApplyResult result) {
    final results = {for (final op in result.results) op.clientOpId: op};
    final targets = Map.of(_state.targets);
    for (final entry in _state.targets.entries) {
      final target = entry.value;
      final slot = target.inFlight;
      final outcome = results[slot?.op.clientOpId];
      if (slot == null || outcome == null) continue;
      final rejected = outcome.status == ConstellationAnchorOpStatus.rejected;
      _outcomes.remove(slot.op.clientOpId)?.complete(!rejected);
      final pending =
          target.latestPending ??
          (slot.discardOnSettle
              ? (rejected ? null : _compensation(slot, outcome))
              : rejected && slot.op.ifRevision == null
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

  /// Undoes a confirmed write the user discarded while it was in flight.
  PlacementSlot? _compensation(
    PlacementSlot slot,
    ConstellationAnchorOpResult outcome,
  ) {
    final baseline = slot.preOpConfirmed;
    final target = slot.op.target;
    final ifRevision = outcome.resultingTargetRevision;
    final PlacementOp op;
    if (baseline != null) {
      op = PlacementOp.upsert(
        clientOpId: _uuid.v4(),
        clusterId: _uuid.v4(),
        target: target,
        position: baseline.position,
        ifRevision: ifRevision,
        baseRevision: _baseRevision,
      );
    } else if (slot.op is PlacementUpsert) {
      op = PlacementOp.delete(
        clientOpId: _uuid.v4(),
        clusterId: _uuid.v4(),
        target: target,
        ifRevision: ifRevision,
        baseRevision: _baseRevision,
      );
    } else {
      return null;
    }
    return PlacementSlot(op: op, status: PlacementSlotStatus.queued);
  }

  void _emit(PlacementOutboxState state) {
    _state = state;
    // The episode ends once nothing is left unacknowledged.
    if (state.targets.values.every((t) => t.inFlight == null)) {
      _noticeRaised = false;
    }
    _changes.add(state);
  }

  Future<void> dispose() async {
    _disposed = true;
    _failOutcomes();
    _retryHandle?.cancel();
    _retryHandle = null;
    _cancelOverdue();
    _replayBarrier?.complete();
    _replayBarrier = null;
    _applyBarrier?.complete();
    _applyBarrier = null;
    _store.holdCatchUpReads(null);
    _store.holdAnchorHints(null);
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _changes.close();
    await _notices.close();
  }
}
