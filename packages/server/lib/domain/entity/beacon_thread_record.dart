import 'package:tentura_server/domain/entity/coordination_item_with_counts.dart';

/// Fixed preview discriminator codes — mirrored verbatim on the client.
abstract final class ThreadMessagePreviewKind {
  static const text = 0;
  static const attachment = 1;
  static const planUpdated = 2;
  static const factPinned = 3;
  static const participantStatus = 4;
  static const coordination = 5;
  static const needInfo = 6;
  static const done = 7;
  static const poll = 8;
  static const join = 9;
}

final class ThreadMessagePreviewRecord {
  const ThreadMessagePreviewRecord({
    required this.kind,
    this.excerpt,
    required this.hasAttachment,
    this.joinedUserId,
    this.admissionReason,
    this.linkedItemId,
    this.linkedEventKind,
    this.itemKind,
    this.itemTitle,
    this.pollTitle,
    this.factTitle,
    this.factVisibility,
  });

  final int kind;
  final String? excerpt;
  final bool hasAttachment;
  final String? joinedUserId;
  final String? admissionReason;
  final String? linkedItemId;
  final int? linkedEventKind;
  final int? itemKind;
  final String? itemTitle;
  final String? pollTitle;
  final String? factTitle;
  final int? factVisibility;
}

final class BeaconThreadRecord {
  const BeaconThreadRecord({
    required this.threadId,
    required this.threadKind,
    required this.unreadCount,
    required this.messageCount,
    this.lastSeenAt,
    this.lastMessageAt,
    this.lastMessageAuthorId,
    this.lastMessagePreview,
    this.item,
  });

  final String threadId;
  final String threadKind;
  final int unreadCount;
  final int messageCount;
  final DateTime? lastSeenAt;
  final DateTime? lastMessageAt;
  final String? lastMessageAuthorId;
  final ThreadMessagePreviewRecord? lastMessagePreview;
  final CoordinationItemWithCounts? item;
}
