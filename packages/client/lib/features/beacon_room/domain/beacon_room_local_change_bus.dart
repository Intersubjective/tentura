import 'dart:async';

import 'package:injectable/injectable.dart';

import 'entity/beacon_room_invalidation.dart';

/// Session-local beacon room invalidations produced after successful own writes.
///
/// Every successful local mutation that changes beacon-visible room/coordination
/// state emits the same `BeaconRoomInvalidation`-shaped event that a remote WS
/// invalidation would have produced. List/detail screens subscribe to one merged
/// stream and silently refetch the affected beacon.
@lazySingleton
class BeaconRoomLocalChangeBus {
  final _controller = StreamController<BeaconRoomInvalidation>.broadcast();

  Stream<BeaconRoomInvalidation> get changes => _controller.stream;

  void notify(BeaconRoomInvalidation invalidation) {
    if (_controller.isClosed) return;
    _controller.add(invalidation);
  }

  void notifyBeaconChanged({
    required String beaconId,
    required BeaconRoomEntityType entityType,
  }) {
    notify(
      BeaconRoomInvalidation(
        beaconId: beaconId,
        entityType: entityType,
      ),
    );
  }

  @disposeMethod
  Future<void> dispose() async {
    await _controller.close();
  }
}
