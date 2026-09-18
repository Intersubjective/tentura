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
    bool? canCloseNow,
    bool? canReopen,
    DateTime? sentAt,
    @Default(0) int requiredTotal,
    @Default(0) int requiredReviewed,
    @Default(0) int optionalTotal,
    @Default(0) int optionalReviewed,
    @Default(false) bool viewerPackageOptional,
    @Default(false) bool allRequiredSent,
    @Default(0) int sentReviewerCount,
    @Default(0) int unsentStartedPackages,
  }) = _ReviewWindowInfo;

  const ReviewWindowInfo._();
}
