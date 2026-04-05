import 'package:injectable/injectable.dart';

import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/data/repository/evaluation_repository.dart';

/// Test env: no-op evaluation persistence.
@Injectable(
  as: EvaluationRepository,
  env: [Environment.test],
  order: 1,
)
class EvaluationRepositoryMock implements EvaluationRepository {
  const EvaluationRepositoryMock();

  @override
  Future<void> closeExpiredWindows() async {}

  @override
  Future<int> countDistinctEvaluatorsForEvaluated({
    required String beaconId,
    required String evaluatedUserId,
  }) async =>
      0;

  @override
  Future<BeaconEvaluation?> getEvaluation({
    required String beaconId,
    required String evaluatorId,
    required String evaluatedUserId,
  }) async =>
      null;

  @override
  Future<BeaconReviewWindow?> getReviewWindow(String beaconId) async => null;

  @override
  Future<int?> getReviewUserStatus(String beaconId, String userId) async => null;

  @override
  Future<List<BeaconEvaluation>> listEvaluationsForEvaluatedUser({
    required String beaconId,
    required String evaluatedUserId,
  }) async =>
      [];

  @override
  Future<List<BeaconEvaluationParticipant>> listParticipants(
    String beaconId,
  ) async =>
      [];

  @override
  Future<List<BeaconEvaluationVisibilityData>> listVisibilityForEvaluator(
    String beaconId,
    String evaluatorId,
  ) async =>
      [];

  @override
  Future<List<BeaconEvaluationVisibilityData>> listAllVisibility(
    String beaconId,
  ) async =>
      [];

  @override
  Future<List<BeaconEvaluation>> listDraftRowsForBeacon(String beaconId) async =>
      [];

  @override
  Future<void> deleteEvaluationRow({
    required String beaconId,
    required String evaluatorId,
    required String evaluatedUserId,
  }) async {}

  @override
  Future<void> finalizeSubmittedEvaluationsForBeacon(String beaconId) async {}

  @override
  Future<void> deleteDraftEvaluationsForBeacon(String beaconId) async {}

  @override
  Future<void> insertParticipant({
    required String beaconId,
    required String userId,
    required int role,
    required String contributionSummary,
    required String causalHint,
  }) async {}

  @override
  Future<void> insertReviewStatus({
    required String beaconId,
    required String userId,
    int status = 0,
  }) async {}

  @override
  Future<void> insertReviewWindow({
    required String beaconId,
    required DateTime openedAt,
    required DateTime closesAt,
  }) async {}

  @override
  Future<void> insertVisibility({
    required String beaconId,
    required String evaluatorId,
    required String participantId,
  }) async {}

  @override
  Future<void> setReviewUserStatus({
    required String beaconId,
    required String userId,
    required int status,
  }) async {}

  @override
  Future<void> upsertEvaluation({
    required String beaconId,
    required String evaluatorId,
    required String evaluatedUserId,
    required int value,
    required String reasonTagsCsv,
    required String note,
    int status = 1,
  }) async {}
}
