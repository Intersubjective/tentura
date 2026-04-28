import 'package:freezed_annotation/freezed_annotation.dart';

part 'room_message.freezed.dart';

@freezed
abstract class RoomMessage with _$RoomMessage {
  const factory RoomMessage({
    required String id,
    required String beaconId,
    required String authorId,
    required String body,
    required DateTime createdAt,
    int? semanticMarker,
    String? linkedBlockerId,
    String? systemPayloadJson,
  }) = _RoomMessage;
}
