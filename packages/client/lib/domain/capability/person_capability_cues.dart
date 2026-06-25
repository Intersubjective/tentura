import 'package:freezed_annotation/freezed_annotation.dart';

import 'capability_group.dart';
import 'capability_tag.dart';

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

  /// Slugs from forward-reason counts (server order: count desc, then slug).
  List<String> get forwardedForSlugs =>
      forwardReasonsByMe.map((e) => e.slug).toList();

  /// Unique commit-role slugs, first-seen order.
  List<String> get commitRoleSlugs => slugsFromBeaconRefs(commitRoles);

  /// Unique close-ack slugs written by the viewer about the subject.
  List<String> get closeAckSlugs => slugsFromBeaconRefs(closeAckByMe);

  /// Unique close-ack slugs about the viewer (self profile only).
  List<String> get closeAckAboutMeSlugs =>
      slugsFromBeaconRefs(closeAckAboutMe);

  /// Non-manual slugs from the viewer-visible subjective list.
  Set<String> get automaticViewerVisibleSlugs => viewerVisible
      .where((c) => !c.hasManualLabel)
      .map((c) => c.slug)
      .toSet();

  /// Network card cue line: strongest tier only
  /// (closeAck > commitRole > forwardReason > privateLabel).
  List<String> get strongestNetworkCueSlugs {
    if (closeAckSlugs.isNotEmpty) return closeAckSlugs;
    if (commitRoleSlugs.isNotEmpty) return commitRoleSlugs;
    if (forwardedForSlugs.isNotEmpty) return forwardedForSlugs;
    return List<String>.from(privateLabels);
  }

  /// Profile beacon-scoped strip: closeAckAboutMe beats commitRoles.
  List<String> get profileBeaconCueSlugs {
    if (closeAckAboutMeSlugs.isNotEmpty) return closeAckAboutMeSlugs;
    return commitRoleSlugs;
  }

  /// Unique slugs from beacon-scoped refs, preserving first-seen order.
  static List<String> slugsFromBeaconRefs(Iterable<TagBeaconRef> refs) {
    final seen = <String>{};
    final result = <String>[];
    for (final ref in refs) {
      if (seen.add(ref.slug)) {
        result.add(ref.slug);
      }
    }
    return result;
  }

  /// Groups known capability slugs by [CapabilityGroup].
  ///
  /// Unknown slugs are omitted. Within each group, slugs follow [CapabilityTag]
  /// enum order (same as [CapabilityChipSet]).
  static Map<CapabilityGroup, List<String>> groupSlugsByCapabilityGroup(
    Iterable<String> slugs,
  ) {
    final slugSet = slugs.toSet();
    final grouped = <CapabilityGroup, List<String>>{};
    for (final tag in CapabilityTag.values) {
      if (!slugSet.contains(tag.slug)) continue;
      grouped.putIfAbsent(tag.group, () => []).add(tag.slug);
    }
    return grouped;
  }

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
