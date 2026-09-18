import 'package:tentura_server/domain/evaluation/evaluation_participant_role.dart';

final class EvaluationParticipantDraft {
  const EvaluationParticipantDraft({
    required this.userId,
    required this.role,
    required this.contributionSummary,
    required this.causalHint,
    this.committedAt,
    this.offerMessage = '',
    this.forwarderDisplayName,
  });

  final String userId;
  final EvaluationParticipantRole role;
  final String contributionSummary;
  final String causalHint;

  /// Structured context for client-side localization. The legacy text fields
  /// above stay written verbatim (D9); these never carry English prose.
  final DateTime? committedAt;
  final String offerMessage;
  final String? forwarderDisplayName;
}
