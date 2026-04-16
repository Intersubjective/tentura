import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/domain/entity/evaluation/beacon_evaluation_record.dart';

BeaconEvaluationRecord beaconEvaluationToRecord(BeaconEvaluation r) =>
    BeaconEvaluationRecord(
      beaconId: r.beaconId,
      evaluatorId: r.evaluatorId,
      evaluatedUserId: r.evaluatedUserId,
      value: r.value,
      reasonTags: r.reasonTags,
      note: r.note,
      status: r.status,
      createdAt: r.createdAt.dateTime,
      updatedAt: r.updatedAt.dateTime,
    );

BeaconEvaluationParticipantRecord beaconEvaluationParticipantToRecord(
  BeaconEvaluationParticipant r,
) => BeaconEvaluationParticipantRecord(
  beaconId: r.beaconId,
  userId: r.userId,
  role: r.role,
  contributionSummary: r.contributionSummary,
  causalHint: r.causalHint,
);

BeaconEvaluationVisibilityRecord beaconEvaluationVisibilityToRecord(
  BeaconEvaluationVisibilityData r,
) => BeaconEvaluationVisibilityRecord(
  beaconId: r.beaconId,
  evaluatorId: r.evaluatorId,
  participantId: r.participantId,
);

BeaconReviewWindowRecord beaconReviewWindowToRecord(BeaconReviewWindow r) =>
    BeaconReviewWindowRecord(
      beaconId: r.beaconId,
      openedAt: r.openedAt.dateTime,
      closesAt: r.closesAt.dateTime,
      status: r.status,
      createdAt: r.createdAt.dateTime,
      updatedAt: r.updatedAt.dateTime,
    );
