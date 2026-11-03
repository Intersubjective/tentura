import 'package:tentura_root/domain/entity/beacon_status.dart';

/// Viewer-specific conversation preview for an open or closed Post.
final class PostSummary {
  const PostSummary({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.authorAvatar,
    this.forwardedById,
    this.forwardedByName,
    this.rootImageUrl,
    required this.rootExcerpt,
    required this.lastMessageExcerpt,
    this.lastMessageIsRoot = false,
    required this.lastMessageAt,
    required this.lastActivityAt,
    required this.pinnedAt,
    required this.mutedUntil,
    required this.unreadCount,
    required this.isAuthor,
    this.status = BeaconStatus.open,
    this.mutedForever = false,
    this.expiresAt,
    this.participantCount = 0,
    this.notOpenedCount = 0,
    this.myDeclinedForwardCount = 0,
    this.previewParticipants = const [],
  });

  final int participantCount;
  final int notOpenedCount;
  final int myDeclinedForwardCount;
  final List<PostParticipantPreview> previewParticipants;

  final String id;
  final String authorId;
  final String authorName;
  final String authorAvatar;

  /// Latest active inbound sender other than the Post author, if any.
  final String? forwardedById;
  final String? forwardedByName;

  /// First image attached to the Post root message, in attachment order.
  final String? rootImageUrl;
  final String? rootExcerpt;
  final String? lastMessageExcerpt;

  /// Whether the latest non-system message is the Post root, by identity.
  final bool lastMessageIsRoot;
  final DateTime? lastMessageAt;
  final DateTime? lastActivityAt;
  final DateTime? pinnedAt;
  final DateTime? mutedUntil;

  /// Muted with no expiry; [mutedUntil] is null then, as it is when the
  /// viewer has no mute at all.
  final bool mutedForever;
  final int unreadCount;
  final bool isAuthor;

  /// [BeaconStatus.open], or [BeaconStatus.closed] for a Post closed by
  /// budding (it stays in the list, read-only).
  final BeaconStatus status;

  /// When the Post expires; null for a row with no recorded expiry.
  final DateTime? expiresAt;
}

/// Display identity of an admitted peer in a Post conversation.
final class PostParticipantPreview {
  const PostParticipantPreview({
    required this.id,
    required this.displayName,
    required this.avatar,
  });

  final String id;
  final String displayName;
  final String avatar;
}
