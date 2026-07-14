import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:meta/meta.dart';

import 'package:tentura/domain/entity/realtime/realtime_catch_up.dart';
import 'package:tentura/domain/entity/realtime/realtime_connection_status.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/entity/realtime/realtime_watch.dart';
import 'package:tentura/domain/port/realtime_sync_port.dart';

/// UI-facing application boundary for realtime projection convergence.
@singleton
final class RealtimeSyncCase {
  RealtimeSyncCase(RealtimeSyncPort syncPort)
    : this._(syncPort, DateTime.timestamp);

  @visibleForTesting
  RealtimeSyncCase.forTesting(
    RealtimeSyncPort syncPort, {
    required DateTime Function() now,
  }) : this._(syncPort, now);

  RealtimeSyncCase._(this._syncPort, this._now) {
    _connectionSubscription = connectionStatuses.listen(_onConnectionStatus);
  }

  final RealtimeSyncPort _syncPort;
  final DateTime Function() _now;
  late final StreamSubscription<RealtimeConnectionStatus>
  _connectionSubscription;

  final _watchRefreshController =
      StreamController<RealtimeWatchScope>.broadcast();
  final _watchGrants = <RealtimeWatchScope, RealtimeWatchGrant>{};
  final _watchRenewalTimers = <RealtimeWatchScope, Timer>{};
  String? _activeAccountId;
  int? _authenticatedEpoch;

  Stream<RealtimeEntityChange> get entityChanges => _syncPort.entityChanges;
  Stream<RealtimeCatchUp> get catchUps => _syncPort.catchUps;
  Stream<RealtimeConnectionStatus> get connectionStatuses =>
      _syncPort.connectionStatuses;

  /// Projection owners refetch their snapshot and replace the grant on this
  /// signal. The case never extends authorization from a stale descriptor.
  Stream<RealtimeWatchScope> get watchRefreshRequests =>
      _watchRefreshController.stream;

  void requestCatchUp(RealtimeCatchUpReason reason) =>
      _syncPort.requestCatchUp(reason);

  void replaceWatch(RealtimeWatchGrant grant) {
    _watchRenewalTimers.remove(grant.scope)?.cancel();
    _watchGrants[grant.scope] = grant;
    if (grant.expiresAt.isAfter(_now())) {
      _syncPort.replaceWatch(grant);
      _scheduleRenewal(grant);
    } else {
      _requestWatchRefresh(grant.scope);
    }
  }

  void removeWatch(RealtimeWatchScope scope) {
    _watchRenewalTimers.remove(scope)?.cancel();
    _watchGrants.remove(scope);
    _syncPort.removeWatch(scope);
  }

  Stream<RealtimeEntityChange> changesFor(Set<RealtimeEntityKind> kinds) =>
      entityChanges.where((change) => kinds.contains(change.kind));

  Stream<RealtimeEntityChange> changesForAggregate({
    required Set<RealtimeEntityKind> kinds,
    required String aggregateId,
  }) => changesFor(
    kinds,
  ).where((change) => change.aggregateId == aggregateId);

  void _onConnectionStatus(RealtimeConnectionStatus status) {
    if (status.phase == RealtimeConnectionPhase.unbound ||
        (status.accountId != null &&
            _activeAccountId != null &&
            status.accountId != _activeAccountId)) {
      _clearWatches();
      _activeAccountId = status.accountId;
      _authenticatedEpoch = null;
      return;
    }
    if (!status.isAuthenticated || status.accountId == null) return;

    final wasAuthenticated = _authenticatedEpoch != null;
    final isNewGeneration =
        status.accountId != _activeAccountId ||
        status.connectionEpoch != _authenticatedEpoch;
    _activeAccountId = status.accountId;
    if (!isNewGeneration) return;
    _authenticatedEpoch = status.connectionEpoch;

    for (final grant in _watchGrants.values.toList(growable: false)) {
      if (grant.expiresAt.isAfter(_now())) {
        _syncPort.replaceWatch(grant);
      }
      if (wasAuthenticated) _requestWatchRefresh(grant.scope);
    }
  }

  void _scheduleRenewal(RealtimeWatchGrant grant) {
    final ttl = grant.expiresAt.difference(_now());
    if (ttl <= Duration.zero) {
      _requestWatchRefresh(grant.scope);
      return;
    }
    final lead = ttl > const Duration(seconds: 45)
        ? const Duration(seconds: 30)
        : Duration(microseconds: ttl.inMicroseconds ~/ 3);
    _watchRenewalTimers[grant.scope] = Timer(ttl - lead, () {
      if (identical(_watchGrants[grant.scope], grant)) {
        _requestWatchRefresh(grant.scope);
      }
    });
  }

  void _requestWatchRefresh(RealtimeWatchScope scope) {
    if (!_watchRefreshController.isClosed) {
      _watchRefreshController.add(scope);
    }
  }

  void _clearWatches() {
    for (final timer in _watchRenewalTimers.values) {
      timer.cancel();
    }
    _watchRenewalTimers.clear();
    _watchGrants.clear();
  }

  /// Cancels the singleton's transport subscription and renewal timers.
  @disposeMethod
  Future<void> dispose() async {
    _clearWatches();
    await _connectionSubscription.cancel();
    await _watchRefreshController.close();
  }
}
