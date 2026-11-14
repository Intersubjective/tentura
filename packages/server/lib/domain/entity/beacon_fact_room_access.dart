import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura_server/consts/beacon_fact_card_consts.dart';

part 'beacon_fact_room_access.freezed.dart';

/// Preflight access check for fact-card operations on a beacon room.
@freezed
abstract class BeaconFactRoomAccess with _$BeaconFactRoomAccess {
  const factory BeaconFactRoomAccess({
    required int beaconStatus,
    required bool canUseRoom,
    required bool canReadContent,
    required bool exists,
    required int kind,
    required bool isDraft,
    required bool isExpiredPost,
  }) = _BeaconFactRoomAccess;
}

/// Plan §4.4 fact access rule for reading one fact of this beacon.
extension BeaconFactReadRule on BeaconFactRoomAccess {
  /// A live request-visible fact needs content read; a discussion-only fact
  /// needs the room. A removed fact is never readable.
  bool canReadFact({required int status, required int visibility}) =>
      exists &&
      status != BeaconFactCardStatusBits.removed &&
      (visibility == BeaconFactCardVisibilityBits.public
          ? canReadContent
          : canUseRoom);
}
