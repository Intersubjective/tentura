abstract class PersonCapabilityEventRepositoryPort {
  /// Replaces the full private-label set for [observerId]+[subjectId].
  /// Soft-deletes removed slugs; upserts new ones.
  Future<void> upsertPrivateLabels({
    required String observerId,
    required String subjectId,
    required List<String> slugs,
  });

  /// Returns current active private-label slugs [observerId] has for [subjectId].
  Future<List<String>> fetchPrivateLabels({
    required String observerId,
    required String subjectId,
  });

  /// Inserts one forward-reason event per slug for the given forward edge.
  Future<void> insertForwardReasons({
    required String observerId,
    required String subjectId,
    required String beaconId,
    required List<String> slugs,
    String note = '',
  });

  /// Inserts a commit-role event (beacon-scoped visibility).
  Future<void> insertCommitRole({
    required String observerId,
    required String subjectId,
    required String beaconId,
    required String slug,
  });

  /// Inserts close-acknowledgement events (one per slug).
  Future<void> insertCloseAcknowledgements({
    required String observerId,
    required String subjectId,
    required String beaconId,
    required List<String> slugs,
  });

  /// Returns aggregated cues visible to [viewerId] about [subjectId].
  Future<PersonCapabilityCuesRow> fetchCues({
    required String viewerId,
    required String subjectId,
  });

  /// Inserts a tombstone (is_negative=true) for [observerId]+[subjectId]+[slug].
  /// No-op if an active tombstone already exists.
  Future<void> insertTombstone({
    required String observerId,
    required String subjectId,
    required String slug,
  });

  /// Soft-deletes the active tombstone for [observerId]+[subjectId]+[slug].
  /// No-op if no active tombstone exists.
  Future<void> deleteTombstone({
    required String observerId,
    required String subjectId,
    required String slug,
  });

  /// Returns deduplicated capability slugs visible to [viewerId] on [subjectId]'s
  /// profile after applying tombstone filtering. Each row carries a hasManualLabel
  /// flag indicating whether the viewer explicitly added the slug as a private label.
  Future<List<ViewerVisibleCapabilityRow>> fetchDeduplicatedCapabilities({
    required String viewerId,
    required String subjectId,
  });
}

class PersonCapabilityCuesRow {
  const PersonCapabilityCuesRow({
    required this.privateLabels,
    required this.forwardReasonsByMe,
    required this.commitRoles,
    required this.closeAckByMe,
    required this.closeAckAboutMe,
  });

  final List<String> privateLabels;
  final List<TagCountRow> forwardReasonsByMe;
  final List<TagBeaconRefRow> commitRoles;
  final List<TagBeaconRefRow> closeAckByMe;
  final List<TagBeaconRefRow> closeAckAboutMe;
}

class TagCountRow {
  const TagCountRow({
    required this.slug,
    required this.count,
    required this.lastSeenAt,
  });

  final String slug;
  final int count;
  final String lastSeenAt;
}

class ViewerVisibleCapabilityRow {
  const ViewerVisibleCapabilityRow({
    required this.slug,
    required this.hasManualLabel,
  });

  final String slug;
  final bool hasManualLabel;
}

class TagBeaconRefRow {
  const TagBeaconRefRow({
    required this.slug,
    required this.beaconId,
    required this.beaconTitle,
    required this.createdAt,
  });

  final String slug;
  final String beaconId;
  final String beaconTitle;
  final String createdAt;
}
