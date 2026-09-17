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
    required this.isOptional,
    required this.rowStatus,
    this.committedAt,
    this.offerMessage = '',
    this.forwarderDisplayName,
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

  /// True when this target's role is formerCommitter: reviewing them is optional
  /// and never gates the package (#180).
  final bool isOptional;

  /// BeaconEvaluationRowStatus of the stored row, or -1 when there is no row.
  final int rowStatus;

  /// When this target committed to the request, or null (m0176).
  final DateTime? committedAt;

  /// The target's help-offer message, or empty (m0176).
  final String offerMessage;

  /// Display name of whoever forwarded the request to this target (m0176).
  final String? forwarderDisplayName;
}
