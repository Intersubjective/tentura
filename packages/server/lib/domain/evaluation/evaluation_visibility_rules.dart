import 'package:tentura_server/domain/entity/forward_edge_entity.dart';
import 'package:tentura_server/domain/evaluation/evaluation_participant_role.dart';

/// One directed edge: [evaluatorId] may evaluate [participantId].
final class EvaluationVisibilityPair {
  const EvaluationVisibilityPair({
    required this.evaluatorId,
    required this.participantId,
  });

  final String evaluatorId;
  final String participantId;
}

/// Participant slice needed to compute evaluation visibility (no DB types).
final class EvaluationVisibilityParticipant {
  const EvaluationVisibilityParticipant({
    required this.userId,
    required this.role,
  });

  final String userId;
  final EvaluationParticipantRole role;
}

/// Pure visibility graph for post-beacon review (who may rate whom).
/// Forwarders are **subjects only** — they never appear as [evaluatorId].
List<EvaluationVisibilityPair> buildEvaluationVisibility({
  required String authorId,
  required List<EvaluationVisibilityParticipant> participants,
  required Map<String, ForwardEdgeEntity> latestEdgeToCommitter,
}) {
  final byId = {for (final p in participants) p.userId: p};
  final out = <EvaluationVisibilityPair>[];

  void add(String a, String b) {
    if (a != b) {
      out.add(EvaluationVisibilityPair(evaluatorId: a, participantId: b));
    }
  }

  for (final e in participants) {
    final eid = e.userId;
    if (e.role == EvaluationParticipantRole.author) {
      for (final p in participants) {
        if (p.userId == authorId) {
          continue;
        }
        add(eid, p.userId);
      }
      continue;
    }
    if (e.role == EvaluationParticipantRole.committer ||
        e.role == EvaluationParticipantRole.formerCommitter) {
      add(eid, authorId);
      for (final p in participants) {
        if ((p.role == EvaluationParticipantRole.committer ||
                p.role == EvaluationParticipantRole.formerCommitter) &&
            p.userId != eid) {
          add(eid, p.userId);
        }
      }
      final edge = latestEdgeToCommitter[e.userId];
      if (edge != null) {
        final fwd = edge.senderId;
        if (fwd != authorId && byId.containsKey(fwd)) {
          add(eid, fwd);
        }
      }
      continue;
    }
    // Forwarders do not leave reviews (subjects only).
  }

  return out;
}
