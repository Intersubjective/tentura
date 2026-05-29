import 'dart:async';

import 'package:injectable/injectable.dart';

/// Session-scoped per-beacon main-room read watermarks (survives route pushes).
///
/// Distinguishes local read-through (user reached bottom) from server-confirmed
/// sync (mark-seen mutation succeeded).
@lazySingleton
class RoomReadWatermarkStore {
  final _changesController = StreamController<String>.broadcast();

  /// Local read-through per beacon (monotonic max).
  final Map<String, DateTime> _readThroughByBeacon = {};

  /// Last server-confirmed watermark per beacon.
  final Map<String, DateTime> _syncedByBeacon = {};

  /// Emits [beaconId] when read-through or synced watermark changes.
  Stream<String> get changes => _changesController.stream;

  DateTime? readThrough(String beaconId) => _readThroughByBeacon[beaconId];

  DateTime? syncedAt(String beaconId) => _syncedByBeacon[beaconId];

  /// True when local read-through is ahead of the last confirmed server watermark.
  bool hasPendingSync(String beaconId) {
    final local = _readThroughByBeacon[beaconId];
    if (local == null) return false;
    final synced = _syncedByBeacon[beaconId];
    return synced == null || local.isAfter(synced);
  }

  /// Advances local read-through monotonically; returns whether it changed.
  bool observeReadThrough(String beaconId, DateTime at) {
    final prev = _readThroughByBeacon[beaconId];
    if (prev != null && !at.isAfter(prev)) return false;
    _readThroughByBeacon[beaconId] = at;
    if (!_changesController.isClosed) {
      _changesController.add(beaconId);
    }
    return true;
  }

  /// Records server-confirmed watermark; never regresses below local read-through.
  void confirmSynced(String beaconId, DateTime persistedAt) {
    final local = _readThroughByBeacon[beaconId];
    final effective = local != null && local.isAfter(persistedAt)
        ? local
        : persistedAt;
    final prev = _syncedByBeacon[beaconId];
    _syncedByBeacon[beaconId] = effective;
    if (local == null || persistedAt.isAfter(local)) {
      _readThroughByBeacon[beaconId] = effective;
    }
    if (prev == null || !prev.isAtSameMomentAs(effective)) {
      if (!_changesController.isClosed) {
        _changesController.add(beaconId);
      }
    }
  }

  /// Resolves display unread count from server batch + local read-through.
  int resolveUnread({
    required String beaconId,
    required int serverCount,
    required DateTime? serverSeenAt,
  }) {
    if (serverCount == 0) return 0;
    final local = _readThroughByBeacon[beaconId];
    if (local == null) return serverCount;
    if (serverSeenAt == null || local.isAfter(serverSeenAt)) {
      return 0;
    }
    return serverCount;
  }

  @disposeMethod
  Future<void> dispose() => _changesController.close();
}
