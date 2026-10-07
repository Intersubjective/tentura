import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

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

  /// V2 returns closure epoch status; older results carry beacon status.
  BeaconStatus get beaconStatus => switch (state) {
    0 => BeaconStatus.reviewOpen,
    1 => BeaconStatus.closed,
    2 => BeaconStatus.cancelled,
    _ => BeaconStatus.fromSmallint(state),
  };
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
