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
  }) = _ReviewFinalizationResult;
}
