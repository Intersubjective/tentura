import 'package:tentura_server/domain/entity/coordination_item_record.dart';

/// Coordination item row plus viewer-scoped discussion counts.
final class CoordinationItemWithCounts {
  const CoordinationItemWithCounts({
    required this.item,
    required this.messageCount,
    required this.unreadCount,
    this.lastSeenAt,
  });

  final CoordinationItemRecord item;
  final int messageCount;
  final int unreadCount;
  final DateTime? lastSeenAt;
}
