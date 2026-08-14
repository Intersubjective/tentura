import 'dart:async';

import 'package:meta/meta.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura/features/auth/domain/use_case/auth_case.dart';

import 'entity/request_thread.dart';

@immutable
final class RoomReadWatermarkKey {
  const RoomReadWatermarkKey(this.beaconId, this.threadId);

  final String beaconId;
  final String threadId;

  @override
  bool operator ==(Object other) =>
      other is RoomReadWatermarkKey &&
      other.beaconId == beaconId &&
      other.threadId == threadId;

  @override
  int get hashCode => Object.hash(beaconId, threadId);
}

/// Session-scoped per-beacon per-thread read watermarks (survives route pushes).
///
/// Distinguishes local read-through (user reached bottom) from server-confirmed
/// sync (mark-seen mutation succeeded).
@lazySingleton
class RoomReadWatermarkStore {
  RoomReadWatermarkStore(AuthCase authCase) {
    _authSubscription = authCase.currentAccountChanges().listen((id) {
      if (id.isEmpty) {
        reset();
      }
    });
  }

  /// Unit tests without auth lifecycle wiring.
  @visibleForTesting
  RoomReadWatermarkStore.testing();

  StreamSubscription<String>? _authSubscription;

  final _threadChangesController =
      StreamController<RoomReadWatermarkKey>.broadcast();

  /// Local read-through per thread key (monotonic max).
  final Map<RoomReadWatermarkKey, DateTime> _readThroughByKey = {};

  /// Last server-confirmed watermark per thread key.
  final Map<RoomReadWatermarkKey, DateTime> _syncedByKey = {};

  /// Emits the full thread key when read-through or synced watermark changes.
  Stream<RoomReadWatermarkKey> get threadChanges =>
      _threadChangesController.stream;

  /// Legacy General-only projection for Beacon View, Inbox, and My Work.
  Stream<String> get changes => threadChanges
      .where((key) => key.threadId == RequestThread.generalId)
      .map((key) => key.beaconId);

  RoomReadWatermarkKey _key(String beaconId, String threadId) =>
      RoomReadWatermarkKey(beaconId, threadId);

  DateTime? readThrough(
    String beaconId, {
    String threadId = RequestThread.generalId,
  }) =>
      _readThroughByKey[_key(beaconId, threadId)];

  DateTime? syncedAt(
    String beaconId, {
    String threadId = RequestThread.generalId,
  }) =>
      _syncedByKey[_key(beaconId, threadId)];

  /// True when local read-through is ahead of the last confirmed server watermark.
  bool hasPendingSync(
    String beaconId, {
    String threadId = RequestThread.generalId,
  }) {
    final key = _key(beaconId, threadId);
    final local = _readThroughByKey[key];
    if (local == null) return false;
    final synced = _syncedByKey[key];
    return synced == null || local.isAfter(synced);
  }

  /// Advances local read-through monotonically; returns whether it changed.
  bool observeReadThrough(
    String beaconId,
    DateTime at, {
    String threadId = RequestThread.generalId,
  }) {
    final key = _key(beaconId, threadId);
    final prev = _readThroughByKey[key];
    if (prev != null && !at.isAfter(prev)) return false;
    _readThroughByKey[key] = at;
    if (!_threadChangesController.isClosed) {
      _threadChangesController.add(key);
    }
    return true;
  }

  /// Records server-confirmed watermark; never regresses below local read-through.
  void confirmSynced(
    String beaconId,
    DateTime persistedAt, {
    String threadId = RequestThread.generalId,
  }) {
    final key = _key(beaconId, threadId);
    final local = _readThroughByKey[key];
    final effective = local != null && local.isAfter(persistedAt)
        ? local
        : persistedAt;
    final prev = _syncedByKey[key];
    _syncedByKey[key] = effective;
    if (local == null || persistedAt.isAfter(local)) {
      _readThroughByKey[key] = effective;
    }
    if (prev == null || !prev.isAtSameMomentAs(effective)) {
      if (!_threadChangesController.isClosed) {
        _threadChangesController.add(key);
      }
    }
  }

  /// Resolves display unread count from server batch + local read-through.
  int resolveUnread({
    required String beaconId,
    required int serverCount,
    required DateTime? serverSeenAt,
    String threadId = RequestThread.generalId,
  }) {
    if (serverCount == 0) return 0;
    final local = _readThroughByKey[_key(beaconId, threadId)];
    if (local == null) return serverCount;
    if (serverSeenAt == null || local.isAfter(serverSeenAt)) {
      return 0;
    }
    return serverCount;
  }

  /// Clears all session-scoped watermark state (e.g. on auth reset).
  void reset() {
    _readThroughByKey.clear();
    _syncedByKey.clear();
  }

  @disposeMethod
  Future<void> dispose() async {
    await _authSubscription?.cancel();
    await _threadChangesController.close();
  }
}
