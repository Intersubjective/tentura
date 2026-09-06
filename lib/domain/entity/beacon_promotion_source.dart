import 'beacon_hierarchy_owner_summary.dart';

/// Composer-only authorized preview of a promotion source message.
class BeaconPromotionSource {
  const BeaconPromotionSource({
    required this.sourceBeaconId,
    required this.sourceMessageId,
    required this.textPreview,
    required this.author,
  });

  final String sourceBeaconId;
  final String sourceMessageId;
  final String textPreview;
  final BeaconHierarchyOwnerSummary author;
}
