import '../entity/room_message_snapshot.dart';

/// Loads eligible room message snapshots (plain text, fact system lines
/// 10/11, quotes) for realtime paint.
abstract interface class RoomMessageSnapshotLookupPort {
  Future<RoomMessageSnapshot?> findEligibleInsert({
    required String messageId,
    required String beaconId,
  });
}
