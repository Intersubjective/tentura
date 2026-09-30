import 'package:injectable/injectable.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/entity/beacon_status_transition.dart';
import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/capability/capability_consts.dart';
import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/domain/evaluation/beacon_evaluation_value.dart';
import 'package:tentura_server/domain/entity/gql_public/evaluation_received_result.dart';
import 'package:tentura_server/domain/evaluation/evaluation_participant_role.dart';
import 'package:tentura_server/domain/evaluation/evaluation_received_trust_tone.dart';
import 'package:tentura_server/domain/entity/review_close_snapshot.dart';
import 'package:tentura_server/domain/entity/review_finalization_result.dart';
import 'package:tentura_server/domain/port/capability_evidence_port.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_repository_port.dart';
import 'package:tentura_server/domain/port/evaluation_repository_port.dart';
import 'package:tentura_server/domain/port/attention_system_settlement_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';
import 'package:tentura_server/domain/port/review_finalization_port.dart';

import '../_use_case_base.dart';

@Singleton(as: ReviewFinalizationPort, order: 2)
final class ReviewFinalizationCase extends UseCaseBase
    implements ReviewFinalizationPort {
  ReviewFinalizationCase(
    this._unitOfWork,
    this._evaluationRepository,
    this._capabilityEvidence,
    this._hierarchyRepository,
    this._lifecycleEffects,
    this._attentionSystemSettlement, {
    required super.env,
    required super.logger,
  });

  final MutatingUnitOfWorkPort _unitOfWork;
  final EvaluationRepositoryPort _evaluationRepository;
  final CapabilityEvidencePort _capabilityEvidence;
  final BeaconHierarchyRepositoryPort _hierarchyRepository;
  final BeaconLifecycleEffectsCase _lifecycleEffects;
  final AttentionSystemSettlementPort _attentionSystemSettlement;

  static const _outcomeEligibleRoles = {
    EvaluationParticipantRole.author,
    EvaluationParticipantRole.committer,
    EvaluationParticipantRole.formerCommitter,
  };

  Future<ReviewFinalizationResult> closeAndFinalize(
    String beaconId, {
    required String reason,
    String? actorUserId,
    bool requireAllRequiredPackagesSent = false,
  }) =>
      _unitOfWork.run<ReviewFinalizationResult>(
        actorUserId: actorUserId,
        action: () async {
          await _hierarchyRepository.lockMutationScope();
          final snapshot = await _evaluationRepository.closeReviewWindow(
            beaconId,
            reason: reason,
            actorUserId: actorUserId,
            requireAllRequiredPackagesSent: requireAllRequiredPackagesSent,
          );
          if (snapshot == null) {
            return const ReviewFinalizationResult(didClose: false);
          }

          await _attentionSystemSettlement
              .settleReviewObligationsAfterWindowClose(beaconId);
          final expiredReviewerAccountIds = await _attentionSystemSettlement
              .listExpiredReviewObligationAccountIds(beaconId);

          await _lifecycleEffects.recordEligibleSourceTransition(
            sourceBeaconId: beaconId,
            fromStatus: BeaconStatus.reviewOpen,
            toStatus: BeaconStatus.closed,
            occurredAt: DateTime.timestamp(),
            actorUserId: actorUserId,
            reason: _hierarchyReasonForFinalClose(reason),
          );

          await _recordOutcomeEvidence(snapshot);
          return ReviewFinalizationResult(
            didClose: true,
            beaconTitle: snapshot.beaconTitle,
            pairs: _finalizedTrustPairs(snapshot),
            expiredReviewerAccountIds: expiredReviewerAccountIds,
          );
        },
      );

  List<FinalizedTrustPair> _finalizedTrustPairs(ReviewCloseSnapshot snapshot) {
    final pairs = <FinalizedTrustPair>[];
    for (final ev in snapshot.finalizedEvaluations) {
      final tone = evaluationReceivedTrustToneFromValue(ev.value);
      if (tone == EvaluationReceivedTrustTone.noBasis) continue;
      pairs.add(
        FinalizedTrustPair(
          evaluatorId: ev.evaluatorId,
          evaluatedUserId: ev.evaluatedUserId,
          tone: tone,
        ),
      );
    }
    return pairs;
  }

  Future<void> _recordOutcomeEvidence(ReviewCloseSnapshot snapshot) async {
    final acknowledgersBySubjectTag = <String, Map<String, Set<String>>>{};

    for (final ev in snapshot.finalizedEvaluations) {
      if (!_qualifiesForOutcomeEmission(ev)) {
        continue;
      }
      final tagsBySubject = acknowledgersBySubjectTag.putIfAbsent(
        ev.evaluatedUserId,
        () => {},
      );
      for (final tag in ev.ackTags) {
        tagsBySubject.putIfAbsent(tag, () => {}).add(ev.evaluatorId);
      }
    }

    if (acknowledgersBySubjectTag.isEmpty) {
      return;
    }

    final emissions = <OutcomeEmission>[];
    final sortedSubjects = acknowledgersBySubjectTag.keys.toList()..sort();
    for (final subjectId in sortedSubjects) {
      final tagsByAcknowledgers = acknowledgersBySubjectTag[subjectId]!;
      final rankedTags = tagsByAcknowledgers.keys.toList()
        ..sort((a, b) {
          final countCmp = tagsByAcknowledgers[b]!
              .length
              .compareTo(tagsByAcknowledgers[a]!.length);
          if (countCmp != 0) {
            return countCmp;
          }
          return a.compareTo(b);
        });
      for (final tag in rankedTags.take(kCapMaxTagsPerSubjectBeacon)) {
        final observers = tagsByAcknowledgers[tag]!.toList()..sort();
        for (final observerId in observers) {
          emissions.add(
            OutcomeEmission(
              observerUserId: observerId,
              subjectUserId: subjectId,
              tagSlug: tag,
            ),
          );
        }
      }
    }

    if (emissions.isEmpty) {
      return;
    }

    await _capabilityEvidence.emitOutcomeEvidenceBatch(
      beaconId: snapshot.beaconId,
      emissions: emissions,
    );
  }

  bool _qualifiesForOutcomeEmission(FinalizedEvaluation ev) {
    if (!BeaconEvaluationValue.isPositive(ev.value)) {
      return false;
    }
    final role = EvaluationParticipantRole.fromDb(ev.role);
    if (!_outcomeEligibleRoles.contains(role)) {
      return false;
    }
    return ev.ackTags.isNotEmpty;
  }

  static BeaconStatusTransitionReason _hierarchyReasonForFinalClose(
    String reason,
  ) =>
      switch (reason) {
        BeaconLifecycleChangeReason.reviewExpired =>
          BeaconStatusTransitionReason.reviewExpired,
        BeaconLifecycleChangeReason.authorCloseNow =>
          BeaconStatusTransitionReason.authorCloseNow,
        _ => BeaconStatusTransitionReason.directClose,
      };
}
