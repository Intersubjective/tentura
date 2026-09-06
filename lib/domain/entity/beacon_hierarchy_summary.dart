import 'beacon_hierarchy_owner_summary.dart';
import 'beacon_status.dart';

/// One child card in a parent hierarchy list projection.
class BeaconHierarchySummary {
  const BeaconHierarchySummary({
    required this.beaconId,
    required this.status,
    required this.publishedAt,
    required this.isTombstone,
    this.title,
    this.owner,
  });

  final String beaconId;
  final String? title;
  final BeaconHierarchyOwnerSummary? owner;
  final BeaconStatus status;
  final DateTime publishedAt;
  final bool isTombstone;
}
