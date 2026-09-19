import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura_server/domain/trust/trust_bin.dart';

part 'review_finalization_result.freezed.dart';

@freezed
abstract class FinalizedTrustPair with _$FinalizedTrustPair {
  const factory FinalizedTrustPair({
    required String evaluatorId,
    required String evaluatedUserId,
    required TrustBin bin,
  }) = _FinalizedTrustPair;
}

@freezed
abstract class ReviewFinalizationResult with _$ReviewFinalizationResult {
  const factory ReviewFinalizationResult({
    required bool didClose,
    String? beaconTitle,
    @Default([]) List<FinalizedTrustPair> pairs,
    /// Reviewers whose obligation ended as `expired` in this close — the
    /// window shut before their package arrived (§5: they are owed an
    /// explanation for the count that fell).
    @Default(<String>[]) List<String> expiredReviewerAccountIds,
  }) = _ReviewFinalizationResult;
}
