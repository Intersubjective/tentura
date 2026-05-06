import 'package:freezed_annotation/freezed_annotation.dart';

part 'beacon_participant.freezed.dart';

@freezed
abstract class BeaconParticipant with _$BeaconParticipant {
  const factory BeaconParticipant({
    required String id,
    required String beaconId,
    required String userId,
    required int role,
    required int status,
    required int roomAccess,
    required DateTime createdAt,
    required DateTime updatedAt,
    @Default('') String userTitle,
    @Default(false) bool userHasPicture,
    @Default(0) int userPicHeight,
    @Default(0) int userPicWidth,
    @Default('') String userBlurHash,
    @Default('') String userImageId,
    @Default('') String offerNote,
    String? nextMoveText,
    int? nextMoveStatus,
    int? nextMoveSource,
    String? linkedMessageId,

    /// When this user last read the beacon room (`beacon_participant.last_seen_room_at`).
    DateTime? lastSeenRoomAt,
  }) = _BeaconParticipant;
}
