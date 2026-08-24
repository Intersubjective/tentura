import 'package:meta/meta.dart';

import 'package:tentura_server/domain/entity/gql_public/evaluation_received_result.dart';

/// One finalized review [authorOfReviewsId] wrote about [viewerId], enriched for
/// profile display (tone mapped in the use case).
@immutable
class EvaluationsWrittenAboutViewerRow {
  const EvaluationsWrittenAboutViewerRow({
    required this.beaconId,
    required this.beaconTitle,
    required this.beaconClosedAt,
    required this.evaluatorId,
    required this.evaluatedUserId,
    required this.value,
    required this.tone,
    required this.reasonTags,
    this.acknowledgedHelpTags = const [],
    required this.note,
    required this.occurredAt,
  });

  final String beaconId;
  final String beaconTitle;
  final DateTime? beaconClosedAt;
  final String evaluatorId;
  final String evaluatedUserId;
  final int value;
  final EvaluationReceivedTrustTone tone;
  final List<String> reasonTags;
  final List<String> acknowledgedHelpTags;
  final String note;
  final DateTime occurredAt;
}
