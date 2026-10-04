/// Viewer-specific conversation preview for an open Post.
final class PostSummary {
  const PostSummary({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.authorAvatar,
    this.rootImageUrl,
    required this.rootExcerpt,
    required this.lastMessageExcerpt,
    required this.lastMessageAt,
    required this.lastActivityAt,
    required this.pinnedAt,
    required this.mutedUntil,
    required this.unreadCount,
    required this.isAuthor,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String authorAvatar;

  /// First image attached to the Post root message, in attachment order.
  final String? rootImageUrl;
  final String? rootExcerpt;
  final String? lastMessageExcerpt;
  final DateTime? lastMessageAt;
  final DateTime? lastActivityAt;
  final DateTime? pinnedAt;
  final DateTime? mutedUntil;
  final int unreadCount;
  final bool isAuthor;
}
