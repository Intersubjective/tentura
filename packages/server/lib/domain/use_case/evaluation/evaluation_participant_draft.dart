import 'package:tentura_server/domain/evaluation/evaluation_participant_role.dart';

final class EvaluationParticipantDraft {
  const EvaluationParticipantDraft({
    required this.userId,
    required this.role,
    required this.contributionSummary,
    required this.causalHint,
  });

  final String userId;
  final EvaluationParticipantRole role;
  final String contributionSummary;
  final String causalHint;
}
