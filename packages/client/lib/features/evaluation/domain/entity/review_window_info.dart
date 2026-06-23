import 'package:freezed_annotation/freezed_annotation.dart';

part 'review_window_info.freezed.dart';

@freezed
abstract class ReviewWindowInfo with _$ReviewWindowInfo {
  const factory ReviewWindowInfo({
    required String beaconId,
    required bool hasWindow,
    @Default('') String beaconTitle,
    String? openedAt,
    String? closesAt,
    @Default(false) bool windowComplete,
    int? userReviewStatus,
    @Default(0) int reviewedCount,
    @Default(0) int totalCount,
    @Default(0) int extensionsUsed,
  }) = _ReviewWindowInfo;

  const ReviewWindowInfo._();

  /// True when the current viewer is enrolled and still in the review flow.
  bool get viewerHasOutstandingReviewWork {
    if (!hasWindow || windowComplete || totalCount <= 0) return false;
    final st = userReviewStatus;
    if (st == null || st < 0) return false;
    if (st >= 2) return false;
    return true;
  }
}
