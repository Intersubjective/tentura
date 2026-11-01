import 'package:freezed_annotation/freezed_annotation.dart';

part 'realtime_read_cursor.freezed.dart';

/// The signed-in reader's own persisted room read cursor (`room_seen`), so
/// each of their sessions converges unread without refetching the room.
@freezed
abstract class RealtimeReadCursor with _$RealtimeReadCursor {
  const factory RealtimeReadCursor({
    /// Questions item id; null for the Request's Discussion.
    required String? threadItemId,
    required DateTime lastSeenAt,
  }) = _RealtimeReadCursor;
}
