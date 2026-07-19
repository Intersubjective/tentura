import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/evaluation/beacon_evaluation_value.dart';
import 'package:tentura_server/domain/evaluation/evaluation_participant_role.dart';
import 'package:tentura_server/domain/entity/review_close_snapshot.dart';
import 'package:tentura_server/domain/port/evaluation_repository_port.dart';
import 'package:tentura_server/domain/port/forward_attribution_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';
import 'package:tentura_server/domain/port/trust_evidence_repository_port.dart';
import 'package:tentura_server/domain/trust/forward/forward_outcome_finalizer.dart';
import 'package:tentura_server/domain/trust/forward/forward_outcome_policy.dart';
import 'package:tentura_server/domain/trust/forward/forward_provenance.dart';
import 'package:tentura_server/domain/trust/trust_bin.dart';
import 'package:tentura_server/domain/trust/trust_context.dart';
import 'package:tentura_server/domain/trust/trust_evidence.dart';
import 'package:tentura_server/domain/trust/trust_evidence_metadata.dart';
import 'package:tentura_server/domain/trust/trust_math.dart';
import 'package:tentura_server/domain/trust/trust_source_type.dart';

import '../_use_case_base.dart';

@Singleton(as: ReviewFinalizationPort, order: 2)
final class ReviewFinalizationCase extends UseCaseBase
    implements ReviewFinalizationPort {
  ReviewFinalizationCase(
    this._unitOfWork,
    this._evaluationRepository,
    this._forwardEdgeRepository,
    this._forwardAttributionRepository,
    this._helpOfferRepository,
    this._trustEvidenceRepository, {
    required super.env,
    required super.logger,
  });

  final MutatingUnitOfWorkPort _unitOfWork;
  final EvaluationRepositoryPort _evaluationRepository;
  final ForwardEdgeRepositoryPort _forwardEdgeRepository;
  final ForwardAttributionRepositoryPort _forwardAttributionRepository;
  final HelpOfferRepositoryPort _helpOfferRepository;
  final TrustEvidenceRepositoryPort _trustEvidenceRepository;

  Future<bool> closeAndFinalize(
    String beaconId, {
    required String reason,
    String? actorUserId,
  }) =>
      _unitOfWork.run<bool>(
        actorUserId: actorUserId,
        action: () async {
          final snapshot = await _evaluationRepository.closeReviewWindow(
            beaconId,
            reason: reason,
            actorUserId: actorUserId,
          );
          if (snapshot == null) return false;

          final now = DateTime.timestamp();
          await _recordCommitmentEvidence(snapshot, at: now);
          await _recordForwardEvidence(snapshot, at: now);
          return true;
        },
      );

  Future<void> _recordCommitmentEvidence(
    ReviewCloseSnapshot snapshot, {
    required DateTime at,
  }) async {
    final batchesBySource = <String, List<TrustEvidence>>{};
    for (final ev in snapshot.finalizedEvaluations) {
      final bin = reviewValueToBin(ev.value);
      if (bin == null) continue;
      batchesBySource
          .putIfAbsent(ev.evaluatorId, () => [])
          .add(
            TrustEvidence(
              targetUserId: ev.evaluatedUserId,
              bin: bin,
              count: kTrustReviewEvidenceCount,
              context: TrustContext.commitment,
              sourceType: TrustSourceType.finalizedRequestEvaluation,
              requestId: snapshot.beaconId,
              sourceId:
                  '${snapshot.beaconId}:${ev.evaluatorId}:${ev.evaluatedUserId}',
            ),
          );
    }

    final sortedSources = batchesBySource.keys.toList()..sort();
    for (final source in sortedSources) {
      await _trustEvidenceRepository.record(
        TrustEvidenceBatch(
          sourceUserId: source,
          at: at,
          items: batchesBySource[source]!,
        ),
      );
    }
  }

  Future<void> _recordForwardEvidence(
    ReviewCloseSnapshot snapshot, {
    required DateTime at,
  }) async {
    final participants = await _evaluationRepository.listParticipants(
      snapshot.beaconId,
    );
    final committerIds = participants
        .where((p) => p.role == EvaluationParticipantRole.committer.dbValue)
        .map((p) => p.userId)
        .toSet();

    final authorEvaluations = <String, int>{};
    for (final ev in snapshot.finalizedEvaluations) {
      if (ev.evaluatorId != snapshot.beaconAuthorId) continue;
      if (!committerIds.contains(ev.evaluatedUserId)) continue;
      if (mapAuthorEvaluationToForwardOutcome(ev.value) == null) continue;
      authorEvaluations[ev.evaluatedUserId] = ev.value;
    }
    if (authorEvaluations.isEmpty) return;

    if (await _trustEvidenceRepository.hasForwardEvidenceForRequest(
      snapshot.beaconId,
    )) {
      logger.info(
        'forward_finalization_skipped_existing_episode beacon=${snapshot.beaconId}',
      );
      return;
    }

    final edges = await _forwardEdgeRepository.fetchAllByBeaconId(
      snapshot.beaconId,
    );
    final provenance = [
      for (final e in edges)
        ForwardProvenanceEdge(
          id: e.id,
          senderId: e.senderId,
          recipientId: e.recipientId,
          createdAt: e.createdAt,
          parentEdgeId: e.parentEdgeId,
          batchId: e.batchId,
          cancelledAt: e.cancelledAt,
        ),
    ];

    final batchIds = edges
        .map((e) => e.batchId)
        .whereType<String>()
        .toSet()
        .toList();
    final attributions = await _forwardAttributionRepository.fetchByBatchIds(
      batchIds,
    );
    final attributionsByBatch = <String, List<ForwardAttributionInput>>{};
    for (final attr in attributions) {
      attributionsByBatch
          .putIfAbsent(attr.childForwardBatchId, () => [])
          .add(
            ForwardAttributionInput(
              batchId: attr.childForwardBatchId,
              parentForwardEdgeId: attr.parentForwardEdgeId,
              weight: attr.weight,
            ),
          );
    }

    final helpOffers = await _helpOfferRepository.fetchAllByBeaconId(
      snapshot.beaconId,
    );
    final commitmentAtByCommitter = <String, DateTime>{
      for (final offer in helpOffers) offer.userId: offer.createdAt,
    };
    for (final committerId in authorEvaluations.keys) {
      commitmentAtByCommitter.putIfAbsent(
        committerId,
        () => snapshot.windowOpenedAt,
      );
    }

    final result = ForwardOutcomeFinalizer().compute(
      authorId: snapshot.beaconAuthorId,
      finalizedAt: at,
      authorEvaluationByCommitter: authorEvaluations,
      commitmentAtByCommitter: commitmentAtByCommitter,
      allEdges: provenance,
      attributionsByBatchId: attributionsByBatch,
      minOpportunity: env.forwardMinOpportunity,
      unsuccessfulCount: env.forwardNoEffectCount,
    );

    logger.info(
      'forward_finalization_diagnostics beacon=${snapshot.beaconId} '
      '${result.diagnostics}',
    );

    final forwardBatches = <String, List<TrustEvidence>>{};
    for (final cell in result.propagatedOutcomes) {
      forwardBatches
          .putIfAbsent(cell.senderId, () => [])
          .add(
            TrustEvidence(
              targetUserId: cell.recipientId,
              bin: cell.bin,
              count: cell.count,
              context: TrustContext.forward,
              sourceType: cell.sourceType,
              requestId: snapshot.beaconId,
              sourceId:
                  '${snapshot.beaconId}:${cell.senderId}:${cell.recipientId}:'
                  '${cell.bin.key}:${cell.sourceType.key}',
              metadata: TrustEvidenceMetadata(
                algorithmVersion: kForwardAlgorithmVersion,
              ),
            ),
          );
    }
    for (final pair in result.unsuccessfulPairs) {
      forwardBatches
          .putIfAbsent(pair.$1, () => [])
          .add(
            TrustEvidence(
              targetUserId: pair.$2,
              bin: TrustBin.noEffect,
              count: env.forwardNoEffectCount,
              context: TrustContext.forward,
              sourceType: TrustSourceType.unsuccessfulRequestForward,
              requestId: snapshot.beaconId,
              sourceId:
                  '${snapshot.beaconId}:${pair.$1}:${pair.$2}:unsuccessful',
              metadata: const TrustEvidenceMetadata(
                algorithmVersion: kForwardAlgorithmVersion,
              ),
            ),
          );
    }

    final sortedSenders = forwardBatches.keys.toList()..sort();
    for (final sender in sortedSenders) {
      await _trustEvidenceRepository.record(
        TrustEvidenceBatch(
          sourceUserId: sender,
          at: at,
          items: forwardBatches[sender]!,
        ),
      );
    }
  }
}
