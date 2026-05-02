import 'package:freezed_annotation/freezed_annotation.dart';

part 'person_capability_cues.freezed.dart';

@freezed
abstract class PersonCapabilityCues with _$PersonCapabilityCues {
  const factory PersonCapabilityCues({
    /// Private slugs this viewer has attached to the subject.
    @Default([]) List<String> privateLabels,

    /// Aggregated forward-reason counts (viewer → subject).
    @Default([]) List<TagCount> forwardReasonsByMe,

    /// Subject's commit-role events (beacon-scoped, any viewer).
    @Default([]) List<TagBeaconRef> commitRoles,

    /// Close-ack events written by viewer about subject.
    @Default([]) List<TagBeaconRef> closeAckByMe,

    /// Close-ack events written by others about viewer (only when viewer == subject).
    @Default([]) List<TagBeaconRef> closeAckAboutMe,

    /// Deduplicated, tombstone-filtered list of capabilities visible to the viewer.
    @Default([]) List<CapabilityWithSource> viewerVisible,
  }) = _PersonCapabilityCues;

  const PersonCapabilityCues._();

  bool get isEmpty =>
      privateLabels.isEmpty &&
      forwardReasonsByMe.isEmpty &&
      commitRoles.isEmpty &&
      closeAckByMe.isEmpty &&
      closeAckAboutMe.isEmpty;

  static const empty = PersonCapabilityCues();
}

@freezed
abstract class CapabilityWithSource with _$CapabilityWithSource {
  const factory CapabilityWithSource({
    required String slug,
    /// True when the viewer explicitly added this slug as a private label.
    required bool hasManualLabel,
  }) = _CapabilityWithSource;
}

@freezed
abstract class TagCount with _$TagCount {
  const factory TagCount({
    required String slug,
    required int count,
    required String lastSeenAt,
  }) = _TagCount;
}

@freezed
abstract class TagBeaconRef with _$TagBeaconRef {
  const factory TagBeaconRef({
    required String slug,
    required String beaconId,
    required String beaconTitle,
    required String createdAt,
  }) = _TagBeaconRef;
}
