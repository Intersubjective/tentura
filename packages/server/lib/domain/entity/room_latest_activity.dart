/// U087 — what changed last in one Request's discussion, for the Requests
/// list's "Recent" order and its one-line "latest" preview.
final class RoomLatestActivity {
  const RoomLatestActivity({
    this.lastActivityAt,
    this.lastMessageAt,
    this.lastMessageBody,
    this.lastMessageAuthorId,
    this.lastMessageAuthorName,
    this.lastMessageKind,
  });

  /// Latest of: any main-room line (messages and system lines), the
  /// next-step (`beacon_room_state.updated_at`), any logged event
  /// (`beacon_activity_event`, which carries status changes and also
  /// membership events such as participantJoined and participantRemoved, so
  /// an admission or a removal moves the Request up in "Recent" too) and,
  /// for the author or a steward, the newest help offer
  /// (its `offered` commitment fact, so a re-offer counts too). Null when
  /// nothing happened yet.
  ///
  /// Never moved by reading (`beacon_room_seen` is not an input) nor by the
  /// Request's Questions (W5): a Questions message has a non-null
  /// `thread_item_id`, and nothing in Questions writes an activity event or
  /// the next-step row.
  final DateTime? lastActivityAt;

  /// The latest member-written main-room message (not a system line, and not
  /// a blank message with nothing attached). A message with no text but a
  /// photo, file, poll or quoted fact counts (#498).
  final DateTime? lastMessageAt;
  final String? lastMessageBody;
  final String? lastMessageAuthorId;
  final String? lastMessageAuthorName;

  /// #498 — what the latest message carries when its body is blank:
  /// `image`, `file`, `poll` or `fact`. Null for a text message.
  final String? lastMessageKind;
}
