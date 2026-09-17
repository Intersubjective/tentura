import 'beacon_cover_source.dart';
import 'beacon_hierarchy_owner_summary.dart';
import 'beacon_status.dart';

/// One child card in a parent hierarchy list projection.
///
/// Tombstones have no title, owner, description, media, or helper identities.
class BeaconHierarchySummary {
  const BeaconHierarchySummary({
    required this.beaconId,
    required this.status,
    required this.publishedAt,
    required this.isTombstone,
    this.title,
    this.owner,
    this.description,
    this.coverSource = BeaconCoverSource.photo,
    this.coverImageId,
    this.coverThumbImageId,
    this.primaryNeedSlug,
    this.needs = const {},
    this.statusChangedAt,
    this.admittedHelperPreviews = const [],
    this.admittedHelperCount = 0,
  });

  final String beaconId;
  final String? title;
  final BeaconHierarchyOwnerSummary? owner;
  final BeaconStatus status;
  final DateTime publishedAt;
  final bool isTombstone;

  /// First-party request body; omitted on tombstones.
  final String? description;

  final BeaconCoverSource coverSource;
  final String? coverImageId;
  final String? coverThumbImageId;
  final String? primaryNeedSlug;
  final Set<String> needs;
  final DateTime? statusChangedAt;

  /// Admitted helpers only (author excluded). Pass as the helper list to
  /// [beaconInvolvedPeopleDisplay]; do not prepend the author here.
  final List<BeaconHierarchyOwnerSummary> admittedHelperPreviews;

  /// True admitted-helper total for face-pile overflow (not sample length).
  final int admittedHelperCount;
}
