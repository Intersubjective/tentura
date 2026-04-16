import 'package:tentura_server/domain/entity/forward_edge_entity.dart';
import 'package:tentura_server/domain/evaluation/evaluation_participant_role.dart';

String evaluationPromptVariantForPair({
  required String evaluatorId,
  required int evaluatedRoleDb,
  required String evaluatedUserId,
  required Map<String, ForwardEdgeEntity> latestEdgeToCommitter,
}) {
  final role = EvaluationParticipantRole.fromDb(evaluatedRoleDb);
  if (role != EvaluationParticipantRole.committer) {
    return 'full';
  }
  final edge = latestEdgeToCommitter[evaluatedUserId];
  if (edge != null && edge.senderId == evaluatorId) {
    return 'handoff';
  }
  return 'full';
}
