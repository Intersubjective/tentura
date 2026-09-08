import 'dart:async';

import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';

/// Holds the General room open while ANY presentation needs it.
///
/// Holders are the CHAT tab body and the expanded split's room pane. During a
/// split <-> tab handover both are briefly registered, so the count never
/// reaches zero and the room is reparented rather than torn down.
class BeaconRoomLease {
  BeaconRoomLease({required ThreadHostCubit host}) : _host = host;

  final ThreadHostCubit _host;
  final Set<Object> _holders = {};
  int _dropGeneration = 0;

  /// The open in flight, so every acquirer — not only the one that triggered
  /// the open — can await room readiness. Callers that hand a scroll target to
  /// [RoomCubit.prepareThreadScroll] must await [acquire] first (plan §4.6).
  Future<void>? _openInFlight;

  /// Whether the room is open and settled, with at least one holder.
  bool get isReady =>
      _holders.isNotEmpty && _openInFlight == null && _host.roomCubit != null;

  /// Completes once any in-flight [acquire] open finishes (plan §4.6).
  Future<void> awaitReady() async {
    final open = _openInFlight;
    if (open != null) await open;
  }

  /// Registers [holder] and opens the room when the count goes 0 -> 1.
  ///
  /// Completes only once the room is actually open, for every caller. A second
  /// holder joining mid-open awaits the same in-flight open rather than
  /// returning early against a room that is not there yet.
  Future<void> acquire(Object holder, RequestThread general) async {
    if (_host.isClosed) return;

    // Any non-empty set means an open already happened or is in flight;
    // `contains(holder)` is subsumed by this, so one check covers both the
    // idempotent re-acquire and a second holder joining.
    if (_holders.isNotEmpty) {
      _holders.add(holder);
      await _openInFlight;
      return;
    }

    _holders.add(holder);

    // Cancel a pending deferred drop (fast tab flip / re-acquire).
    _dropGeneration++;

    if (_host.isClosed) return;
    final open = _host.ensureGeneral(general);
    _openInFlight = open;
    try {
      await open;
    } finally {
      if (identical(_openInFlight, open)) _openInFlight = null;
    }
  }

  /// Deregisters [holder]. When the count goes 1 -> 0 the drop is scheduled on
  /// a microtask; a re-[acquire] before it runs CANCELS the drop, so tab-flip
  /// churn never closes the room.
  void release(Object holder) {
    if (_host.isClosed) return;
    if (!_holders.remove(holder)) return;
    if (_holders.isNotEmpty) return;

    final generation = ++_dropGeneration;
    Future.microtask(() {
      if (_host.isClosed) return;
      if (generation != _dropGeneration) return;
      if (_holders.isNotEmpty) return;
      unawaited(_host.clear());
    });
  }

  /// Cancels any pending deferred drop without releasing current holders.
  void dispose() {
    _dropGeneration++;
  }
}
