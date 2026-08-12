import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/domain/entity/evaluation/beacon_evaluation_record.dart';
import 'package:tentura_server/domain/entity/forward_attribution_entity.dart';
import 'package:tentura_server/domain/entity/forward_edge_entity.dart';
import 'package:tentura_server/domain/entity/help_offer_entity.dart';
import 'package:tentura_server/domain/entity/review_close_snapshot.dart';
import 'package:tentura_server/domain/evaluation/evaluation_participant_role.dart';
import 'package:tentura_server/domain/port/capability_evidence_port.dart';
import 'package:tentura_server/domain/port/evaluation_repository_port.dart';
import 'package:tentura_server/domain/port/forward_attribution_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';
import 'package:tentura_server/domain/port/trust_evidence_repository_port.dart';
import 'package:tentura_server/domain/trust/trust_evidence.dart';
import 'package:tentura_server/domain/use_case/evaluation/review_finalization_case.dart';
import 'package:tentura_server/env.dart';

final class PassThroughUoW extends Fake implements MutatingUnitOfWorkPort {
  @override
  Future<T> run<T>({
    required Future<T> Function() action,
    String? actorUserId,
  }) =>
      action();
}

final class FakeEvaluationRepo extends Fake implements EvaluationRepositoryPort {
  ReviewCloseSnapshot? snapshotOnClose;
  String authorParticipantId = 'U-author';
  String committerParticipantId = 'U-committer';

  @override
  Future<ReviewCloseSnapshot?> closeReviewWindow(
    String beaconId, {
    required String reason,
    String? actorUserId,
  }) async =>
      snapshotOnClose;

  @override
  Future<List<BeaconEvaluationParticipantRecord>> listParticipants(
    String beaconId,
  ) async =>
      [
        BeaconEvaluationParticipantRecord(
          beaconId: beaconId,
          userId: authorParticipantId,
          role: EvaluationParticipantRole.author.dbValue,
          contributionSummary: '',
          causalHint: '',
        ),
        BeaconEvaluationParticipantRecord(
          beaconId: beaconId,
          userId: committerParticipantId,
          role: EvaluationParticipantRole.committer.dbValue,
          contributionSummary: '',
          causalHint: '',
        ),
      ];
}

final class FakeForwardEdges extends Fake implements ForwardEdgeRepositoryPort {
  List<ForwardEdgeEntity> edges = const [];

  @override
  Future<List<ForwardEdgeEntity>> fetchAllByBeaconId(String beaconId) async =>
      edges;
}

final class FakeAttribution extends Fake
    implements ForwardAttributionRepositoryPort {
  @override
  Future<List<ForwardAttributionEntity>> fetchByBatchIds(
    List<String> batchIds,
  ) async =>
      [];
}

final class FakeHelpOffers extends Fake implements HelpOfferRepositoryPort {
  List<HelpOfferEntity> offers = const [];

  @override
  Future<List<HelpOfferEntity>> fetchAllByBeaconId(String beaconId) async =>
      offers;
}

final class RecordingTrustEvidence extends Fake
    implements TrustEvidenceRepositoryPort {
  final recorded = <TrustEvidenceBatch>[];
  bool forwardAlreadyRecorded = false;

  @override
  Future<void> record(TrustEvidenceBatch batch) async {
    recorded.add(batch);
  }

  @override
  Future<bool> hasForwardEvidenceForRequest(String requestId) async =>
      forwardAlreadyRecorded;
}

final class NoopCapabilityEvidence extends Fake implements CapabilityEvidencePort {
  @override
  Future<void> emitOutcomeEvidenceBatch({
    required String beaconId,
    required List<OutcomeEmission> emissions,
  }) async {}

  @override
  Future<void> reconcileForwardReasons({
    required String forwardEdgeId,
    required String observerId,
    required String subjectId,
    required List<String> slugs,
  }) async {}

  @override
  Future<void> revokeOutcomeEvidence({
    required String beaconId,
    required String observerId,
    required String subjectId,
    required String slug,
  }) async {}

  @override
  Future<void> upsertSeedAttestation({
    required String observerId,
    required String subjectId,
    required List<String> slugs,
  }) async {}
}

ReviewFinalizationCase buildReviewFinalizationCase({
  required EvaluationRepositoryPort evaluationRepo,
  required ForwardEdgeRepositoryPort forwardEdges,
  required HelpOfferRepositoryPort helpOffers,
  required TrustEvidenceRepositoryPort trustEvidence,
  CapabilityEvidencePort? capabilityEvidence,
  ForwardAttributionRepositoryPort? attribution,
}) =>
    ReviewFinalizationCase(
      PassThroughUoW(),
      evaluationRepo,
      forwardEdges,
      attribution ?? FakeAttribution(),
      helpOffers,
      trustEvidence,
      capabilityEvidence ?? NoopCapabilityEvidence(),
      env: Env(environment: Environment.test),
      logger: Logger('ReviewFinalizationTestSupport'),
    );
