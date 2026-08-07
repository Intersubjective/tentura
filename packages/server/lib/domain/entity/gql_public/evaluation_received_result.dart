import 'package:meta/meta.dart';

import 'package:tentura_server/domain/evaluation/evaluation_participant_role.dart';

/// Trust direction for one received review row (GraphQL `EvaluationReceivedRow.tone`).
enum EvaluationReceivedTrustTone {
  up,
  down,
  noChange,
  noBasis,
}

/// One named review received by the evaluated participant.
@immutable
class EvaluationReceivedRow {
  const EvaluationReceivedRow({
    required this.reviewerId,
    required this.reviewerDisplayName,
    required this.reviewerImageId,
    required this.reviewerRole,
    required this.value,
    required this.tone,
    required this.reasonTags,
    required this.note,
    required this.occurredAt,
  });

  final String reviewerId;
  final String reviewerDisplayName;
  final String reviewerImageId;
  final EvaluationParticipantRole reviewerRole;
  final int value;
  final EvaluationReceivedTrustTone tone;
  final List<String> reasonTags;
  final String note;
  final DateTime occurredAt;
}

/// Named per-reviewer received reviews for one beacon (GraphQL `EvaluationReceived`).
@immutable
class EvaluationReceivedResult {
  const EvaluationReceivedResult({
    required this.beaconId,
    required this.beaconTitle,
    required this.windowClosed,
    required this.rows,
  });

  final String beaconId;
  final String beaconTitle;
  final bool windowClosed;
  final List<EvaluationReceivedRow> rows;
}
