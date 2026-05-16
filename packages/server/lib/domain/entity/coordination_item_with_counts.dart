import 'package:tentura_server/data/database/tentura_db.dart';

/// Coordination item row plus viewer-scoped discussion counts.
final class CoordinationItemWithCounts {
  const CoordinationItemWithCounts({
    required this.item,
    required this.messageCount,
    required this.unreadCount,
    this.lastSeenAt,
  });

  final CoordinationItem item;
  final int messageCount;
  final int unreadCount;
  final DateTime? lastSeenAt;
}
