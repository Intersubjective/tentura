import 'package:freezed_annotation/freezed_annotation.dart';

part 'room_typing_signal.freezed.dart';

/// The server relayed that [userId] started or stopped typing in the
/// discussion of Request [beaconId]. Ephemeral: never stored or replayed.
@freezed
abstract class RoomTypingSignal with _$RoomTypingSignal {
  const factory RoomTypingSignal({
    required String beaconId,
    required String userId,
    required bool typing,
  }) = _RoomTypingSignal;
}
