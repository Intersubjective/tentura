/// U087 — what changed last in one Request's discussion, for the Requests
/// list's "Recent" order and its one-line "latest" preview.
final class RoomLatestActivity {
  const RoomLatestActivity({
    this.lastActivityAt,
    this.lastMessageAt,
    this.lastMessageBody,
    this.lastMessageAuthorId,
    this.lastMessageAuthorName,
  });

  /// Latest of: any main-room line (messages and system lines), the
  /// next-step (`beacon_room_state.updated_at`) and any logged event
  /// (`beacon_activity_event`, which carries status changes and also
  /// membership events such as participantJoined and participantRemoved, so
  /// a join or a removal moves the Request up in "Recent" too). Null when
  /// nothing happened yet.
  final DateTime? lastActivityAt;

  /// The latest member-written main-room message (not a system line, and not
  /// an attachment-only message with an empty body).
  final DateTime? lastMessageAt;
  final String? lastMessageBody;
  final String? lastMessageAuthorId;
  final String? lastMessageAuthorName;
}
