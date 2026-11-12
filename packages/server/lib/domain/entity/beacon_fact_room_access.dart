import 'package:freezed_annotation/freezed_annotation.dart';

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
