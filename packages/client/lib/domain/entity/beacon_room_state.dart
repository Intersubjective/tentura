import 'package:freezed_annotation/freezed_annotation.dart';

part 'beacon_room_state.freezed.dart';

@freezed
abstract class BeaconRoomState with _$BeaconRoomState {
  const factory BeaconRoomState({
    required String beaconId,
    required DateTime updatedAt,
    @Default('') String currentLine,
    String? openBlockerId,
    String? openBlockerTitle,
    String? lastRoomMeaningfulChange,
    String? updatedBy,

    /// Counts changes of [currentLine]; a next-step save sends the one its
    /// editor opened with, and a newer one on the server refuses it (#517).
    @Default(0) int currentLineRevision,
  }) = _BeaconRoomState;
}
