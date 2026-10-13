import 'dart:async';

import 'package:tentura/domain/attention/entity/my_work_beacon_attention.dart';

import 'my_work_test_support.dart';

/// A desk-wide attention read that was issued **before** a later clear.
///
/// The server answers a read with the projection as it was when the read ran;
/// the answer then travels back. Holding one read open and handing back the
/// projection captured at its start is how a slow network delivers exactly
/// that: a reply that is older than the user's last gesture by the time it
/// lands.
final class SlowDeskReadAttentionRepository extends StubAttentionRepository {
  Completer<void>? _armed;
  Completer<void>? _parked;
  final _held = Completer<void>();

  /// Completes once a read is parked waiting for [releaseHeldRead].
  Future<void> get readIsHeld => _held.future;

  /// The next `myWorkAttention` call parks until [releaseHeldRead].
  void holdNextRead() => _armed = Completer<void>();

  void releaseHeldRead() => _parked?.complete();

  @override
  Future<List<MyWorkBeaconAttention>> myWorkAttention(
    Set<String> beaconIds,
  ) async {
    final armed = _armed;
    if (armed == null) return super.myWorkAttention(beaconIds);
    _armed = null;
    _parked = armed;
    final startedWith = [...myWorkAttentionResult];
    _held.complete();
    await armed.future;
    return startedWith;
  }
}
