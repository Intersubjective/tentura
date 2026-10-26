import 'package:flutter/foundation.dart';
import 'package:tentura_root/domain/entity/beacon_post_lifetime.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

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
    this.status = BeaconStatus.open,
    this.expiresAt,
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

  /// [BeaconStatus.open], or [BeaconStatus.closed] once the Post was closed
  /// by budding a Request from it.
  final BeaconStatus status;

  /// Fixed publication deadline; activity does not extend it.
  final DateTime? expiresAt;

  bool get isClosed => status == BeaconStatus.closed;

  bool isArchivedAt(DateTime now) =>
      isClosed ||
      BeaconPostLifetime.isExpired(
        kind: 1,
        status: status,
        expiresAt: expiresAt,
        now: now,
      );

  bool get isPinned => pinnedAt != null;

  /// Mute expiry is silent: past [mutedUntil] the Post is simply not muted.
  bool isMutedAt(DateTime now) =>
      mutedForever || (mutedUntil?.isAfter(now) ?? false);
}
