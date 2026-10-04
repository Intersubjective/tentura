import 'package:flutter/foundation.dart';

/// One Post the viewer is in, as the «Разговоры» tab lists it.
@immutable
final class PostSummary {
  const PostSummary({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.lastActivityAt,
    this.authorAvatar = '',
    this.rootImageUrl,
    this.rootExcerpt = '',
    this.lastMessageExcerpt,
    this.pinnedAt,
    this.mutedUntil,
    this.mutedForever = false,
    this.unreadCount = 0,
    this.isAuthor = false,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String authorAvatar;

  /// First image attached to the Post root message, in attachment order.
  final String? rootImageUrl;
  final String rootExcerpt;
  final String? lastMessageExcerpt;
  final DateTime lastActivityAt;
  final DateTime? pinnedAt;
  final DateTime? mutedUntil;

  /// Muted with no expiry ([mutedUntil] is null then).
  final bool mutedForever;
  final int unreadCount;
  final bool isAuthor;

  bool get isPinned => pinnedAt != null;

  /// Mute expiry is silent: past [mutedUntil] the Post is simply not muted.
  bool isMutedAt(DateTime now) =>
      mutedForever || (mutedUntil?.isAfter(now) ?? false);
}
