import '../entity/room_message_snapshot.dart';

/// Loads eligible plain-text room message snapshots for realtime paint.
abstract interface class RoomMessageSnapshotLookupPort {
  Future<RoomMessageSnapshot?> findEligibleInsert({
    required String messageId,
    required String beaconId,
  });
}
