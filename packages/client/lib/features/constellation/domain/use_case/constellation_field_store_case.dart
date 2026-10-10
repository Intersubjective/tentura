import 'dart:async';

import 'package:injectable/injectable.dart';

import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/domain/port/clock_port.dart';
import 'package:tentura/domain/port/wake_up_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../entity/constellation_anchor_projection.dart';
import '../entity/constellation_field.dart';
import '../entity/constellation_field_store_state.dart';
import '../entity/constellation_projection_params.dart';
import '../port/constellation_account_port.dart';
import '../port/constellation_anchor_repository_port.dart';
import '../port/constellation_repository_port.dart';

export '../entity/constellation_field_store_state.dart';
export '../entity/constellation_projection_params.dart';

/// D8 staleness window (ARCH 7.3): global invalidations refresh a visible
/// field at most once per window. The D8 load model pins its own copy to this.
const kLazyFieldRefreshInterval = Duration(minutes: 5);

/// ARCH 5.9: an anchor write unacknowledged this long after its first
/// dispatch is reported once as overdue.
const kLazyWriteAckTimeout = Duration(seconds: 15);

enum ConstellationRefreshReason {
  /// Explicit load: dispatched at once, sharing an in-flight read.
  load,
  realtime,
  catchUp,
  resume,
  filters,
  preflight,
}

/// One screen's interest in the store; disposing it drops that interest.
abstract interface class StoreLease {
  void setVisible(bool visible);

  void dispose();
}

/// The one owner of constellation server state (read side).
///
/// The account generation follows [ConstellationAccountPort] and is
/// independent of leases. Refreshes are single-flight per params binding;
/// a result computed for an earlier binding or account generation is ignored.
@Order(2)
@singleton
final class ConstellationFieldStoreCase extends UseCaseBase {
  ConstellationFieldStoreCase(
    this._repository,
    ConstellationAccountPort account,
    this._clock,
    this._wakeUp,
    this._realtimeSyncCase, {
    required super.env,
    required super.logger,
  }) {
    _subscriptions = [
      account.currentAccountChanges.listen(_onAccountChanged),
      _realtimeSyncCase
          .changesFor(const {
            RealtimeEntityKind.beacon,
            RealtimeEntityKind.forward,
            RealtimeEntityKind.participant,
            RealtimeEntityKind.roomMessage,
            RealtimeEntityKind.roomSeen,
            RealtimeEntityKind.constellationField,
          })
          .listen(_onFieldChange),
      _realtimeSyncCase
          .changesFor(const {RealtimeEntityKind.constellationAnchor})
          .listen(_onAnchorChange),
      _realtimeSyncCase.catchUps.listen((_) => unawaited(_onCatchUp())),
    ];
  }

  final ConstellationRepositoryPort _repository;
  final ClockPort _clock;
  final WakeUpPort _wakeUp;
  final RealtimeSyncCase _realtimeSyncCase;

  /// Minimum spacing between urgent realtime-driven FULL refreshes.
  static const _urgentSpacing = Duration(seconds: 2);
  static const _debounce = Duration(milliseconds: 220);

  late final List<StreamSubscription<Object?>> _subscriptions;
  final _changes = StreamController<ConstellationFieldStoreState>.broadcast();
  final _leases = <_StoreLease>{};
  final _accountReady = Completer<void>();

  var _state = ConstellationFieldStoreState(
    field: null,
    coveredRevision: ConstellationAnchorRevision.zero,
    generation: 0,
  );
  var _accountId = '';
  var _params = const ConstellationProjectionParams();
  var _paramsGeneration = 0;
  var _browserVisible = true;
  var _wasVisible = false;

  /// A trigger arrived while nothing could fetch; refresh once when shown.
  var _staleWhileHidden = false;

  WakeUpHandle? _timer;
  DateTime? _dueAt;
  DateTime? _lastFullAt;
  DateTime? _retryNotBefore;
  _FullFlight? _fullInFlight;
  var _queued = false;
  var _queuedUrgent = false;
  var _fullReadSeq = 0;
  var _lastAppliedReadSeq = 0;
  Future<void>? _anchorsInFlight;
  var _anchorsQueued = false;

  /// Newest revision among queued anchor hints, and whether any queued hint
  /// carried none; judged against coverage once the read in flight settles.
  BigInt? _queuedHintRevision;
  var _queuedHintUnreadable = false;

  /// Pending account-owned replays a catch-up read must wait for, if any.
  Future<void>? Function()? _catchUpHold;

  Stream<ConstellationFieldStoreState> get changes => _changes.stream;

  ConstellationFieldStoreState get current => _state;
  ConstellationProjectionParams get projectionParams => _params;

  /// Settle operation slots, then merge the acknowledged rows (ARCH 5.3).
  ///
  /// Executed OK upserts replace their anchor row and bring the record
  /// captured at grab time; executed deletes drop the row and its record.
  /// Replayed and rejected results merge nothing, nor does an ack for
  /// obsolete [params]. Coverage advances only when the batch directly
  /// followed the covered revision.
  void settle(
    ConstellationAnchorApplyResult result,
    void Function() settleSlots, {
    ConstellationProjectionParams? params,
    Iterable<ConstellationPerson> capturedPeers = const [],
    Iterable<ConstellationRequest> capturedRequests = const [],
  }) {
    settleSlots();
    if (params != null && params != _params) return;
    final field =
        _state.field ??
        ConstellationField(
          loadedAt: _clock.now(),
          context: _params.context,
        );
    final held = field.resolvedAnchorProjection;
    final anchors = {for (final a in held.anchors) a.target: a};
    final peers = {for (final p in held.pinnedPeers) p.id: p};
    final requests = {for (final r in held.pinnedRequests) r.id: r};
    final peerRecords = {for (final p in capturedPeers) p.id: p};
    final requestRecords = {for (final r in capturedRequests) r.id: r};
    for (final op in result.results) {
      if (op.status != ConstellationAnchorOpStatus.ok || op.replayed) continue;
      final anchor = op.anchor;
      final target = anchor?.target ?? op.target;
      if (target == null) continue;
      if (anchor == null) {
        anchors.remove(target);
        switch (target.kind) {
          case ConstellationAnchorTargetKind.person:
            peers.remove(target.id);
          case ConstellationAnchorTargetKind.beacon:
            requests.remove(target.id);
        }
        continue;
      }
      anchors[target] = anchor;
      switch (target.kind) {
        case ConstellationAnchorTargetKind.person:
          final record = peerRecords[target.id];
          if (record != null) peers[target.id] = record;
        case ConstellationAnchorTargetKind.beacon:
          final record = requestRecords[target.id];
          if (record != null) requests[target.id] = record;
      }
    }
    final advance =
        result.beforeRevision.compareTo(_state.coveredRevision) == 0;
    _emit(
      ConstellationFieldStoreState(
        field: field.copyWith(
          anchorProjection: ConstellationAnchorProjection(
            revision: advance ? result.afterRevision : held.revision,
            anchors: anchors.values.toList(growable: false),
            pinnedPeers: peers.values.toList(growable: false),
            pinnedRequests: requests.values.toList(growable: false),
            supportPeers: held.supportPeers,
            supportEdges: held.supportEdges,
            serverFilteredBeaconIds: held.serverFilteredBeaconIds,
            serverFilteredBeaconCount: held.serverFilteredBeaconCount,
          ),
        ),
        coveredRevision: advance
            ? result.afterRevision
            : _state.coveredRevision,
        generation: _state.generation,
      ),
    );
  }

  /// Defer the catch-up read until the writer's replay has been dispatched.
  // ignore: use_setters_to_change_properties -- a hook, not a property
  void holdCatchUpReads(Future<void>? Function()? hold) => _catchUpHold = hold;

  bool get _visible => _browserVisible && _leases.any((l) => l.visible);

  bool get _canFetch => _accountId.isNotEmpty && _visible;

  StoreLease lease() {
    final lease = _StoreLease(this);
    _leases.add(lease);
    _onVisibilityChanged();
    return lease;
  }

  /// Browser-tab visibility.
  void setVisible(bool visible) {
    _browserVisible = visible;
    _onVisibilityChanged();
  }

  void setMembershipFilters(ConstellationFieldMembershipFilters filters) {
    setProjectionParams(_params.copyWith(membershipFilters: filters));
  }

  void setProjectionParams(ConstellationProjectionParams params) {
    if (params == _params) {
      return;
    }
    _params = params;
    _paramsGeneration++;
    // Anchors held were computed for the previous params binding.
    if (_state.coveredRevision.compareTo(ConstellationAnchorRevision.zero) !=
        0) {
      _emit(
        ConstellationFieldStoreState(
          field: _state.field,
          coveredRevision: ConstellationAnchorRevision.zero,
          generation: _state.generation,
        ),
      );
    }
    _cancelTimer();
    _queued = false;
    _queuedUrgent = false;
    _lastFullAt = null;
    _retryNotBefore = null;
    _schedule();
  }

  Future<void> requestRefresh(ConstellationRefreshReason reason) async {
    await _accountReady.future;
    if (!_canFetch) {
      _markStale();
      return Future<void>.value();
    }
    if (reason == ConstellationRefreshReason.load ||
        reason == ConstellationRefreshReason.resume ||
        reason == ConstellationRefreshReason.catchUp) {
      return _dispatch();
    }
    _schedule();
    return Future<void>.value();
  }

  Future<void> dispose() async {
    _cancelTimer();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _changes.close();
  }

  Future<void> _onCatchUp() async {
    // Writers hearing the same catch-up register their replay first.
    await Future<void>.value();
    final hold = _catchUpHold?.call();
    if (hold != null) await hold;
    await requestRefresh(ConstellationRefreshReason.catchUp);
  }

  void _emit(ConstellationFieldStoreState state) {
    _state = state;
    if (!_changes.isClosed) {
      _changes.add(state);
    }
  }

  void _onAccountChanged(String accountId) {
    if (!_accountReady.isCompleted) _accountReady.complete();
    if (accountId == _accountId) {
      return;
    }
    _accountId = accountId;
    _params = const ConstellationProjectionParams();
    _paramsGeneration++;
    _cancelTimer();
    _queued = false;
    _queuedUrgent = false;
    _staleWhileHidden = false;
    _lastFullAt = null;
    _retryNotBefore = null;
    _fullInFlight = null;
    _emit(
      ConstellationFieldStoreState(
        field: null,
        coveredRevision: ConstellationAnchorRevision.zero,
        generation: _state.generation + 1,
      ),
    );
  }

  void _onVisibilityChanged() {
    final visible = _visible;
    if (visible == _wasVisible) {
      return;
    }
    _wasVisible = visible;
    if (!visible) {
      if (_timer != null) {
        _markStale();
      }
      _cancelTimer();
      return;
    }
    if (_staleWhileHidden) {
      _staleWhileHidden = false;
      unawaited(_dispatch());
    }
  }

  void _markStale() {
    if (_accountId.isNotEmpty) {
      _staleWhileHidden = true;
    }
  }

  void _onFieldChange(RealtimeEntityChange change) {
    final field = _state.field;
    final fieldBeaconIds = {
      ...?field?.requests.map((r) => r.id),
      ...?field?.posts.map((p) => p.id),
      ...?field?.resolvedAnchorProjection.pinnedRequests.map((r) => r.id),
    };
    _schedule(
      urgent: switch (change.kind) {
        RealtimeEntityKind.constellationField => false,
        RealtimeEntityKind.roomMessage || RealtimeEntityKind.roomSeen =>
          fieldBeaconIds.contains(change.aggregateId),
        _ => true,
      },
    );
  }

  void _onAnchorChange(RealtimeEntityChange change) {
    if (_accountId.isEmpty || change.aggregateId != _accountId) {
      return;
    }
    if (!_canFetch) {
      _markStale();
      return;
    }
    final revision = change.revision;
    if (revision != null && revision <= _state.coveredRevision.value) {
      return;
    }
    if (revision == null) {
      _queuedHintUnreadable = true;
    } else if (_queuedHintRevision == null || revision > _queuedHintRevision!) {
      _queuedHintRevision = revision;
    }
    _anchorsQueued = true;
    unawaited(
      _anchorsInFlight ??= _runAnchorsRefresh().whenComplete(
        () => _anchorsInFlight = null,
      ),
    );
  }

  /// Coalesces realtime-driven FULL refreshes: one refresh per window, never
  /// sooner than [_urgentSpacing] after the previous read (or
  /// [kLazyFieldRefreshInterval] for changes that do not touch the field).
  /// A pending refresh is only ever moved earlier, so a steady event stream
  /// cannot postpone it forever.
  void _schedule({bool urgent = true, bool immediate = false}) {
    if (!_canFetch) {
      _markStale();
      return;
    }
    if (_fullInFlight?.paramsGeneration == _paramsGeneration) {
      _queued = true;
      _queuedUrgent |= urgent;
      return;
    }
    final now = _clock.now();
    final spacing = urgent
        ? _urgentSpacing
        : kLazyFieldRefreshInterval +
              Duration(milliseconds: _accountId.hashCode.abs() % 3001);
    final last = _lastFullAt;
    var dueAt = immediate ? now : now.add(_debounce);
    if (!immediate && last != null && last.add(spacing).isAfter(dueAt)) {
      dueAt = last.add(spacing);
    }
    final retryNotBefore = _retryNotBefore;
    if (retryNotBefore != null && retryNotBefore.isAfter(dueAt)) {
      dueAt = retryNotBefore;
    }
    final pending = _dueAt;
    if (_timer != null && pending != null && !pending.isAfter(dueAt)) {
      return;
    }
    _timer?.cancel();
    _dueAt = dueAt;
    _timer = _wakeUp.schedule(dueAt.difference(now), () {
      _timer = null;
      _dueAt = null;
      if (_canFetch) {
        // Coalesce queued hints before starting the deadline's FULL.
        unawaited(Future<void>.microtask(_dispatch));
      } else {
        _markStale();
      }
    });
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
    _dueAt = null;
  }

  Future<void> _dispatch() {
    if (!_canFetch) {
      _markStale();
      return Future<void>.value();
    }
    final busy = _fullInFlight;
    if (busy != null && busy.paramsGeneration == _paramsGeneration) {
      return busy.future;
    }
    final retryNotBefore = _retryNotBefore;
    if (retryNotBefore != null && _clock.now().isBefore(retryNotBefore)) {
      _schedule(immediate: true);
      return Future<void>.value();
    }
    _cancelTimer();
    return _startFull();
  }

  Future<void> _startFull() {
    final generation = _state.generation;
    final params = _params;
    final paramsGeneration = _paramsGeneration;
    final readSeq = ++_fullReadSeq;
    _lastFullAt = _clock.now();
    final flight = _FullFlight(paramsGeneration);
    flight.future =
        _runFull(
          generation,
          params,
          paramsGeneration,
          readSeq,
        ).whenComplete(() {
          if (!identical(_fullInFlight, flight)) {
            return;
          }
          _fullInFlight = null;
          if (_queued) {
            final urgent = _queuedUrgent;
            _queued = false;
            _queuedUrgent = false;
            _schedule(urgent: urgent, immediate: _retryNotBefore != null);
          }
        });
    _fullInFlight = flight;
    return flight.future;
  }

  Future<void> _runFull(
    int generation,
    ConstellationProjectionParams params,
    int paramsGeneration,
    int readSeq,
  ) async {
    try {
      final field = await _repository.fetch(
        membershipFilters: params.membershipFilters,
      );
      if (generation != _state.generation ||
          paramsGeneration != _paramsGeneration ||
          readSeq < _lastAppliedReadSeq) {
        return;
      }
      _lastAppliedReadSeq = readSeq;
      _retryNotBefore = null;
      // FULL freshness follows read order; the anchor layer only follows
      // anchor revision.
      final incoming = field.resolvedAnchorProjection.revision;
      final adoptAnchors = incoming.compareTo(_state.coveredRevision) >= 0;
      _emit(
        ConstellationFieldStoreState(
          field: adoptAnchors
              ? field
              : field.copyWith(
                  anchorProjection: _state.field?.anchorProjection,
                ),
          coveredRevision: adoptAnchors ? incoming : _state.coveredRevision,
          generation: generation,
        ),
      );
    } on Object catch (error, stackTrace) {
      if (error is RemoteApiRetryLaterException &&
          generation == _state.generation &&
          paramsGeneration == _paramsGeneration) {
        _retryNotBefore = _clock.now().add(error.retryAfter);
        _queued = true;
      }
      logger.warning('Constellation FULL refresh failed', error, stackTrace);
    }
  }

  Future<void> _runAnchorsRefresh() async {
    while (_anchorsQueued) {
      // A FULL in flight reads the anchors too; judge hints once it settles.
      final full = _fullInFlight;
      if (full != null && full.paramsGeneration == _paramsGeneration) {
        await full.future;
      }
      _anchorsQueued = false;
      final hinted = _queuedHintRevision;
      final unreadable = _queuedHintUnreadable;
      _queuedHintRevision = null;
      _queuedHintUnreadable = false;
      if (!_canFetch) {
        _markStale();
        return;
      }
      if (!unreadable &&
          hinted != null &&
          hinted <= _state.coveredRevision.value) {
        continue;
      }
      final generation = _state.generation;
      final params = _params;
      final paramsGeneration = _paramsGeneration;
      try {
        final field = await _repository.fetch(
          membershipFilters: params.membershipFilters,
          projection: ConstellationProjection.anchors,
        );
        if (generation != _state.generation ||
            paramsGeneration != _paramsGeneration) {
          // A FULL still pending for the new params reads the anchors too.
          if (generation == _state.generation && _timer != null) {
            _anchorsQueued = false;
          }
          continue;
        }
        _applyAnchors(field.resolvedAnchorProjection);
      } on Object catch (error, stackTrace) {
        logger.warning(
          'Constellation ANCHORS refresh failed',
          error,
          stackTrace,
        );
      }
    }
  }

  void _applyAnchors(ConstellationAnchorProjection projection) {
    final field =
        _state.field ??
        ConstellationField(
          loadedAt: _clock.now(),
          context: _params.context,
        );
    if (projection.revision.compareTo(_state.coveredRevision) < 0) {
      return;
    }
    _emit(
      ConstellationFieldStoreState(
        field: field.copyWith(anchorProjection: projection),
        coveredRevision: projection.revision,
        generation: _state.generation,
      ),
    );
  }
}

final class _FullFlight {
  _FullFlight(this.paramsGeneration);

  final int paramsGeneration;

  late final Future<void> future;
}

final class _StoreLease implements StoreLease {
  _StoreLease(this._store);

  final ConstellationFieldStoreCase _store;

  bool visible = true;

  @override
  void setVisible(bool visible) {
    if (!_store._leases.contains(this)) {
      return;
    }
    this.visible = visible;
    _store._onVisibilityChanged();
  }

  @override
  void dispose() {
    if (_store._leases.remove(this)) {
      _store._onVisibilityChanged();
    }
  }
}
