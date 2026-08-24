import 'package:meta/meta.dart';

/// One evaluation participant row for review/draft UIs
/// (GraphQL `EvaluationParticipant`).
@immutable
class EvaluationParticipantResult {
  const EvaluationParticipantResult({
    required this.userId,
    required this.displayName,
    required this.imageId,
    required this.role,
    required this.contributionSummary,
    required this.causalHint,
    required this.reasonTags,
    required this.note,
    required this.promptVariant,
    this.acknowledgedHelpTags = const [],
    this.acknowledgeableHelpTags = const [],
    this.maxAcknowledgedHelpTags = 0,
    this.isSubmitted = false,
    this.value,
  });

  final String userId;
  final String displayName;
  final String imageId;
  final int role;
  final String contributionSummary;
  final String causalHint;
  final int? value;
  final List<String> reasonTags;
  final String note;
  final String promptVariant;
  final List<String> acknowledgedHelpTags;
  final List<String> acknowledgeableHelpTags;
  final int maxAcknowledgedHelpTags;
  final bool isSubmitted;
}
