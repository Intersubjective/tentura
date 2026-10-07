import 'dart:async';

import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/port/clock_port.dart';
import 'package:tentura/domain/port/wake_up_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../entity/constellation_anchor_projection.dart';
import '../entity/constellation_field_store_state.dart';
import '../entity/constellation_projection_params.dart';
import '../port/constellation_account_port.dart';
import '../port/constellation_repository_port.dart';
import 'constellation_field_case.dart';

export '../entity/constellation_field_store_state.dart';
export '../entity/constellation_projection_params.dart';

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
          })
          .listen(_onFieldChange),
      _realtimeSyncCase
          .changesFor(const {RealtimeEntityKind.constellationAnchor})
          .listen(_onAnchorChange),
      _realtimeSyncCase.catchUps.listen(
        (_) => unawaited(requestRefresh(ConstellationRefreshReason.catchUp)),
      ),
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
  _FullFlight? _fullInFlight;
  var _queued = false;
  var _queuedUrgent = false;
  var _fullReadSeq = 0;
  var _lastAppliedReadSeq = 0;
  Future<void>? _anchorsInFlight;
  var _anchorsQueued = false;

  Stream<ConstellationFieldStoreState> get changes => _changes.stream;

  ConstellationFieldStoreState get current => _state;
  ConstellationProjectionParams get projectionParams => _params;

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
    _schedule();
  }

  Future<void> requestRefresh(ConstellationRefreshReason reason) {
    if (!_canFetch) {
      _markStale();
      return Future<void>.value();
    }
    if (reason == ConstellationRefreshReason.load) {
      _cancelTimer();
      return _dispatch(queueIfBusy: false);
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

  void _emit(ConstellationFieldStoreState state) {
    _state = state;
    if (!_changes.isClosed) {
      _changes.add(state);
    }
  }

  void _onAccountChanged(String accountId) {
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
      _schedule();
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
      urgent: ConstellationFieldCase.isUrgentFieldChange(
        change,
        fieldBeaconIds,
      ),
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
  void _schedule({bool urgent = true}) {
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
    final spacing = urgent ? _urgentSpacing : kLazyFieldRefreshInterval;
    final last = _lastFullAt;
    var dueAt = now.add(_debounce);
    if (last != null && last.add(spacing).isAfter(dueAt)) {
      dueAt = last.add(spacing);
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
        unawaited(_dispatch(queueIfBusy: true));
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

  Future<void> _dispatch({required bool queueIfBusy}) {
    final busy = _fullInFlight;
    if (busy != null && busy.paramsGeneration == _paramsGeneration) {
      if (queueIfBusy) {
        _queued = true;
      }
      return busy.future;
    }
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
            _schedule(urgent: urgent);
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
      logger.warning('Constellation FULL refresh failed', error, stackTrace);
    }
  }

  Future<void> _runAnchorsRefresh() async {
    while (_anchorsQueued) {
      _anchorsQueued = false;
      if (!_canFetch) {
        _markStale();
        return;
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
    final field = _state.field;
    if (field == null ||
        projection.revision.compareTo(_state.coveredRevision) < 0) {
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
