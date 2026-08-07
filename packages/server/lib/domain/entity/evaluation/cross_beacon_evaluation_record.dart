/// Immutable snapshot of a finalized cross-beacon evaluation row joined to its
/// request (beacon) for profile "reviews from this person" queries.
final class CrossBeaconEvaluationRecord {
  const CrossBeaconEvaluationRecord({
    required this.evaluatorId,
    required this.evaluatedUserId,
    required this.value,
    required this.reasonTags,
    required this.note,
    required this.occurredAt,
    required this.beaconId,
    required this.beaconTitle,
    required this.beaconClosedAt,
  });

  final String evaluatorId;
  final String evaluatedUserId;
  final int value;
  final String reasonTags;
  final String note;
  final DateTime occurredAt;
  final String beaconId;
  final String beaconTitle;

  /// When the request transitioned to closed; null if not recorded.
  final DateTime? beaconClosedAt;
}
