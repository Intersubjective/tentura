import 'package:freezed_annotation/freezed_annotation.dart';

part 'beacon_room_state.freezed.dart';

@freezed
abstract class BeaconRoomState with _$BeaconRoomState {
  const factory BeaconRoomState({
    required String beaconId,
    required DateTime updatedAt,
    @Default('') String currentPlan,
    String? openBlockerId,
    String? openBlockerTitle,
    String? lastRoomMeaningfulChange,
    String? updatedBy,
  }) = _BeaconRoomState;
}
