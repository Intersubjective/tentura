import 'package:freezed_annotation/freezed_annotation.dart';

part 'realtime_room_message_paint.freezed.dart';

/// Optional plain-text room message paint on `room_message` insert invalidations.
@freezed
abstract class RealtimeRoomMessagePaint with _$RealtimeRoomMessagePaint {
  const factory RealtimeRoomMessagePaint({
    required String id,
    required String beaconId,
    required String authorId,
    required String body,
    required DateTime createdAt,
    DateTime? editedAt,
    @Default(<String>[]) List<String> mentions,
    String? threadItemId,
  }) = _RealtimeRoomMessagePaint;
}
