import 'package:meta/meta.dart';

/// Review window snapshot for the viewer (GraphQL `ReviewWindowStatus`).
@immutable
class ReviewWindowStatusResult {
  const ReviewWindowStatusResult({
    required this.beaconId,
    required this.hasWindow,
    required this.beaconTitle,
    this.openedAt,
    this.closesAt,
    this.windowComplete,
    this.userReviewStatus,
    this.reviewedCount,
    this.totalCount,
    this.extensionsUsed,
    this.canCloseNow,
    this.canReopen,
    this.requiredTotal,
    this.requiredReviewed,
    this.optionalTotal,
    this.optionalReviewed,
    this.viewerPackageOptional,
    this.sentAt,
    this.allRequiredSent,
    this.unsentStartedPackages,
    this.sentReviewerCount,
  });

  final String beaconId;
  final bool hasWindow;
  final String beaconTitle;
  final DateTime? openedAt;
  final DateTime? closesAt;
  final bool? windowComplete;
  final int? userReviewStatus;
  final int? reviewedCount;
  final int? totalCount;
  final int? extensionsUsed;
  final bool? canCloseNow;
  final bool? canReopen;

  /// Visible targets whose role is not formerCommitter (viewer-scoped).
  final int? requiredTotal;

  /// Of [requiredTotal], targets with a stored evaluation row.
  final int? requiredReviewed;

  /// Visible targets whose role is formerCommitter (viewer-scoped).
  final int? optionalTotal;

  /// Of [optionalTotal], targets with a stored evaluation row.
  final int? optionalReviewed;

  /// True when the viewer's own role is formerCommitter (#180).
  final bool? viewerPackageOptional;

  /// When the viewer sent their own package, or null.
  final DateTime? sentAt;

  /// Beacon-scoped: author and current committers are all at status 2.
  final bool? allRequiredSent;

  /// Beacon-scoped: reviewers at status 1 (started but not sent).
  final int? unsentStartedPackages;

  /// Beacon-scoped: reviewers at status 2 (sent).
  final int? sentReviewerCount;
}
