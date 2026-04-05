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
  }) = _ReviewWindowInfo;

  const ReviewWindowInfo._();
}
