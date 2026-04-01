/// Role in the evaluation participant table (`beacon_evaluation_participant.role`).
enum EvaluationParticipantRole {
  author(0),
  committer(1),
  forwarder(2);

  const EvaluationParticipantRole(this.dbValue);

  final int dbValue;

  static EvaluationParticipantRole fromDb(int v) => switch (v) {
        0 => EvaluationParticipantRole.author,
        1 => EvaluationParticipantRole.committer,
        2 => EvaluationParticipantRole.forwarder,
        _ => EvaluationParticipantRole.committer,
      };
}
