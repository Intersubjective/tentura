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

/// What to show after fetching the room state: [fetched], except that a next
/// step older than the one [shown] keeps the shown line. A fetch that started
/// before a newer save (or before a refusal reported the newer line) can
/// answer after it; showing it would bring back the old line and make the
/// next save stale (#517).
BeaconRoomState? newestRoomState(
  BeaconRoomState? shown,
  BeaconRoomState? fetched,
) {
  if (shown == null ||
      fetched == null ||
      shown.beaconId != fetched.beaconId ||
      fetched.currentLineRevision >= shown.currentLineRevision) {
    return fetched;
  }
  return fetched.copyWith(
    currentLine: shown.currentLine,
    currentLineRevision: shown.currentLineRevision,
    updatedAt: shown.updatedAt,
    updatedBy: shown.updatedBy,
  );
}
