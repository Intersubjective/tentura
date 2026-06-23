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
}
