import 'package:tentura_server/domain/evaluation/beacon_evaluation_row_status.dart';
import 'package:tentura_server/domain/entity/evaluation/beacon_evaluation_record.dart';

abstract class EvaluationRepositoryPort {
  Future<void> insertReviewWindow({
    required String beaconId,
    required DateTime openedAt,
    required DateTime closesAt,
  });

  Future<BeaconReviewWindowRecord?> getReviewWindow(String beaconId);

  Future<void> insertParticipant({
    required String beaconId,
    required String userId,
    required int role,
    required String contributionSummary,
    required String causalHint,
  });

  Future<void> insertVisibility({
    required String beaconId,
    required String evaluatorId,
    required String participantId,
  });

  Future<void> insertReviewStatus({
    required String beaconId,
    required String userId,
    int status = 0,
  });

  Future<int?> getReviewUserStatus(String beaconId, String userId);

  Future<void> setReviewUserStatus({
    required String beaconId,
    required String userId,
    required int status,
  });

  Future<List<BeaconEvaluationParticipantRecord>> listParticipants(
    String beaconId,
  );

  Future<List<BeaconEvaluationVisibilityRecord>> listVisibilityForEvaluator(
    String beaconId,
    String evaluatorId,
  );

  Future<List<BeaconEvaluationVisibilityRecord>> listAllVisibility(
    String beaconId,
  );

  Future<BeaconEvaluationRecord?> getEvaluation({
    required String beaconId,
    required String evaluatorId,
    required String evaluatedUserId,
  });

  Future<List<BeaconEvaluationRecord>> listEvaluationsForEvaluator({
    required String beaconId,
    required String evaluatorId,
  });

  Future<void> upsertEvaluation({
    required String beaconId,
    required String evaluatorId,
    required String evaluatedUserId,
    required int value,
    required String reasonTagsCsv,
    required String note,
    int status = BeaconEvaluationRowStatus.submitted,
  });

  Future<List<BeaconEvaluationRecord>> listEvaluationsForEvaluatedUser({
    required String beaconId,
    required String evaluatedUserId,
  });

  Future<int> countDistinctEvaluatorsForEvaluated({
    required String beaconId,
    required String evaluatedUserId,
  });

  Future<List<BeaconEvaluationRecord>> listDraftRowsForBeacon(
    String beaconId,
  );

  Future<void> deleteEvaluationRow({
    required String beaconId,
    required String evaluatorId,
    required String evaluatedUserId,
  });

  Future<void> finalizeSubmittedEvaluationsForBeacon(String beaconId);

  Future<void> deleteDraftEvaluationsForBeacon(String beaconId);

  Future<void> closeExpiredWindows();
}
