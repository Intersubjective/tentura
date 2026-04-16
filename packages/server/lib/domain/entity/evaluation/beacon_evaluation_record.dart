/// Immutable snapshot of a `beacon_evaluation` row for domain / use cases.
final class BeaconEvaluationRecord {
  const BeaconEvaluationRecord({
    required this.beaconId,
    required this.evaluatorId,
    required this.evaluatedUserId,
    required this.value,
    required this.reasonTags,
    required this.note,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final String beaconId;
  final String evaluatorId;
  final String evaluatedUserId;
  final int value;
  final String reasonTags;
  final String note;
  final int status;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// Immutable snapshot of `beacon_evaluation_participant`.
final class BeaconEvaluationParticipantRecord {
  const BeaconEvaluationParticipantRecord({
    required this.beaconId,
    required this.userId,
    required this.role,
    required this.contributionSummary,
    required this.causalHint,
  });

  final String beaconId;
  final String userId;
  final int role;
  final String contributionSummary;
  final String causalHint;
}

/// Immutable snapshot of `beacon_evaluation_visibility`.
final class BeaconEvaluationVisibilityRecord {
  const BeaconEvaluationVisibilityRecord({
    required this.beaconId,
    required this.evaluatorId,
    required this.participantId,
  });

  final String beaconId;
  final String evaluatorId;
  final String participantId;
}

/// Immutable snapshot of `beacon_review_window`.
final class BeaconReviewWindowRecord {
  const BeaconReviewWindowRecord({
    required this.beaconId,
    required this.openedAt,
    required this.closesAt,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final String beaconId;
  final DateTime openedAt;
  final DateTime closesAt;
  final int status;
  final DateTime createdAt;
  final DateTime updatedAt;
}
