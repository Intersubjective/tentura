import 'package:freezed_annotation/freezed_annotation.dart';

part 'beacon_close_result.freezed.dart';

@freezed
abstract class BeaconCloseResult with _$BeaconCloseResult {
  const factory BeaconCloseResult({
    required String beaconId,
    required int state,
    String? closesAt,
    @Default(false) bool requiresReviewWindow,
    @Default(false) bool branchMismatch,
  }) = _BeaconCloseResult;

  const BeaconCloseResult._();
}

@freezed
abstract class BeaconExtendReviewResult with _$BeaconExtendReviewResult {
  const factory BeaconExtendReviewResult({
    required String beaconId,
    required String closesAt,
    @Default(0) int extensionsRemaining,
  }) = _BeaconExtendReviewResult;

  const BeaconExtendReviewResult._();
}

@freezed
abstract class BeaconLifecycleMutationResult
    with _$BeaconLifecycleMutationResult {
  const factory BeaconLifecycleMutationResult({
    required String beaconId,
    required int state,
  }) = _BeaconLifecycleMutationResult;

  const BeaconLifecycleMutationResult._();
}
