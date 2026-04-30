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
    @Default('') String offerNote,
    String? nextMoveText,
    int? nextMoveStatus,
    int? nextMoveSource,
    String? linkedMessageId,
  }) = _BeaconParticipant;
}
