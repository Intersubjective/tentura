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

  /// Registers [holder] and opens the room when the count goes 0 -> 1.
  Future<void> acquire(Object holder, RequestThread general) async {
    if (_host.isClosed) return;
    if (_holders.contains(holder)) return;

    final wasEmpty = _holders.isEmpty;
    _holders.add(holder);
    if (!wasEmpty) return;

    // Cancel a pending deferred drop (fast tab flip / re-acquire).
    _dropGeneration++;

    if (_host.isClosed) return;
    await _host.ensureGeneral(general);
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
      _host.clear();
    });
  }

  /// Cancels any pending deferred drop without releasing current holders.
  void dispose() {
    _dropGeneration++;
  }
}
