import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/evaluation/beacon_evaluation_row_status.dart';
import 'package:tentura_server/domain/entity/evaluation/beacon_evaluation_record.dart';
import 'package:tentura_server/domain/entity/evaluation/cross_beacon_evaluation_record.dart';
import 'package:tentura_server/domain/entity/review_close_snapshot.dart';
import 'package:tentura_server/domain/port/evaluation_repository_port.dart';

import '../database/tentura_db.dart';

/// Review-era repository. m0203 (A6) dropped the six review tables
/// (`beacon_evaluation`, `beacon_evaluation_ack_tag`,
/// `beacon_evaluation_participant`, `beacon_evaluation_visibility`,
/// `beacon_review_status`, `beacon_review_window`); A18 deletes these call
/// paths. Every method is stubbed until then.
@Injectable(
  as: EvaluationRepositoryPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class EvaluationRepository implements EvaluationRepositoryPort {
  EvaluationRepository(
    // Kept for DI/call-site arity; the database is unused while every method
    // is an A18 stub.
    // ignore: avoid_unused_constructor_parameters
    TenturaDb db,
  );

  @override
  Future<void> insertReviewWindow({
    required String beaconId,
    required DateTime openedAt,
    required DateTime closesAt,
  }) => throw UnimplementedError('removed in A18');

  @override
  Future<BeaconReviewWindowRecord?> getReviewWindow(String beaconId) =>
      throw UnimplementedError('removed in A18');

  @override
  Future<void> insertParticipant({
    required String beaconId,
    required String userId,
    required int role,
    required String contributionSummary,
    required String causalHint,
    DateTime? committedAt,
    String offerMessage = '',
    String? forwarderDisplayName,
  }) => throw UnimplementedError('removed in A18');

  @override
  Future<void> insertVisibility({
    required String beaconId,
    required String evaluatorId,
    required String participantId,
  }) => throw UnimplementedError('removed in A18');

  @override
  Future<void> insertReviewStatus({
    required String beaconId,
    required String userId,
    int status = 0,
  }) => throw UnimplementedError('removed in A18');

  @override
  Future<int?> getReviewUserStatus(String beaconId, String userId) =>
      throw UnimplementedError('removed in A18');

  @override
  Future<DateTime?> getReviewSentAt(String beaconId, String userId) =>
      throw UnimplementedError('removed in A18');

  @override
  Future<void> setReviewUserStatus({
    required String beaconId,
    required String userId,
    required int status,
    bool markSent = false,
  }) => throw UnimplementedError('removed in A18');

  @override
  Future<List<BeaconEvaluationParticipantRecord>> listParticipants(
    String beaconId,
  ) => throw UnimplementedError('removed in A18');

  @override
  Future<List<BeaconEvaluationVisibilityRecord>> listVisibilityForEvaluator(
    String beaconId,
    String evaluatorId,
  ) => throw UnimplementedError('removed in A18');

  @override
  Future<List<BeaconEvaluationVisibilityRecord>> listAllVisibility(
    String beaconId,
  ) => throw UnimplementedError('removed in A18');

  @override
  Future<BeaconEvaluationRecord?> getEvaluation({
    required String beaconId,
    required String evaluatorId,
    required String evaluatedUserId,
  }) => throw UnimplementedError('removed in A18');

  @override
  Future<List<BeaconEvaluationRecord>> listEvaluationsForEvaluator({
    required String beaconId,
    required String evaluatorId,
  }) => throw UnimplementedError('removed in A18');

  @override
  Future<void> upsertEvaluation({
    required String beaconId,
    required String evaluatorId,
    required String evaluatedUserId,
    required int value,
    required String reasonTagsCsv,
    required String note,
    int status = BeaconEvaluationRowStatus.submitted,
    EvaluationWriteResolver? resolve,
  }) => throw UnimplementedError('removed in A18');

  @override
  Future<void> submitEvaluationAtomic({
    required String beaconId,
    required String evaluatorId,
    required String evaluatedUserId,
    required int value,
    required List<String> reasonTags,
    required String note,
    required List<String> ackTags,
    EvaluationWriteResolver? resolve,
  }) => throw UnimplementedError('removed in A18');

  @override
  Future<List<BeaconEvaluationRecord>> listEvaluationsForEvaluatedUser({
    required String beaconId,
    required String evaluatedUserId,
  }) => throw UnimplementedError('removed in A18');

  @override
  Future<List<CrossBeaconEvaluationRecord>> listFinalizedEvaluationsBetween({
    required String evaluatorId,
    required String evaluatedUserId,
  }) => throw UnimplementedError('removed in A18');

  @override
  Future<List<BeaconEvaluationRecord>> listDraftRowsForBeacon(
    String beaconId,
  ) => throw UnimplementedError('removed in A18');

  @override
  Future<void> deleteEvaluationRow({
    required String beaconId,
    required String evaluatorId,
    required String evaluatedUserId,
  }) => throw UnimplementedError('removed in A18');

  @override
  Future<void> finalizeSubmittedEvaluationsForBeacon(String beaconId) =>
      throw UnimplementedError('removed in A18');

  @override
  Future<void> deleteDraftEvaluationsForBeacon(String beaconId) =>
      throw UnimplementedError('removed in A18');

  @override
  Future<Map<String, int>> listReviewStatusesForBeacon(String beaconId) =>
      throw UnimplementedError('removed in A18');

  @override
  Future<void> downgradeSubmittedReviewsToDraft(String beaconId) =>
      throw UnimplementedError('removed in A18');

  @override
  Future<void> deleteReviewScaffoldingForBeacon(String beaconId) =>
      throw UnimplementedError('removed in A18');

  @override
  Future<DateTime> extendReviewWindow(String beaconId) =>
      throw UnimplementedError('removed in A18');

  @override
  Future<ReviewCloseSnapshot?> closeReviewWindow(
    String beaconId, {
    required String reason,
    String? actorUserId,
    bool requireAllRequiredPackagesSent = false,
  }) => throw UnimplementedError('removed in A18');
}
