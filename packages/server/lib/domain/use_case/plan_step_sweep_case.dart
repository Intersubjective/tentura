import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/plan/plan.dart';

import 'package:tentura_server/consts/beacon_plan_consts.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/beacon_plan.dart';
import 'package:tentura_server/domain/plan/plan_sweep_phase.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_command_port.dart';
import 'package:tentura_server/domain/port/beacon_plan_repository_port.dart';
import 'package:tentura_server/domain/port/closure_repository_port.dart';
import 'package:tentura_server/domain/port/plan_attention_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/plan_attention_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

import '_use_case_base.dart';

/// Request plan («либретто», #220): the time-driven half of plan attention
/// (`plan-implementation.md` §4.5). `TaskWorkerCase` runs it every 30 s when
/// `PLAN_ENABLED`.
///
/// Phases of a live, unticked step of an open-family Request:
/// * `remind` — the assignee, 15 min before start (skipped when the step was
///   set inside that window, when less than 2 min remain, or after a long
///   pause);
/// * `due` — the start came: the plan obligations are reconciled and the head
///   `change_seq` bumps so every client refreshes NOW;
/// * `overdue` — the assignee, once;
/// * `authorLate` — the author, 30 min after the step became overdue;
/// * `unassignedDue` — the author, when a step with nobody on it starts.
///
/// Each phase is claimed once (`beacon_plan_sweep_mark`, key
/// `plan_step:<stepId>:<phase>:<assignee|none>:<epochMs(boundary)>`); a move
/// or a reassignment gives new keys. Every candidate runs in its own
/// transaction and its own `try`, so one failure never stops the pass.
@Singleton(order: 3)
final class PlanStepSweepCase extends UseCaseBase {
  PlanStepSweepCase(
    this._repo,
    this._admission,
    this._store,
    this._closure,
    this._attention,
    this._intents,
    this._planAttention, {
    required super.env,
    required super.logger,
  });

  final BeaconPlanRepositoryPort _repo;

  /// `beacon_effective_admission` of an assignee.
  final BeaconHierarchyCommandPort _admission;
  final PlanAttentionRepositoryPort _store;
  final ClosureRepositoryPort _closure;
  final TransactionalAttentionCase _attention;
  final AttentionIntentCase _intents;
  final PlanAttentionCase _planAttention;

  /// Handles every phase due at [now]; returns how many were claimed.
  Future<int> runDue({DateTime? now}) async {
    if (!env.planEnabled) return 0;
    final instant = (now ?? DateTime.timestamp()).toUtc();
    final candidates = await _store.sweepCandidates(now: instant);
    var claimed = 0;
    for (final candidate in candidates) {
      final phases = PlanSweepPhase.dueAt(
        stepId: candidate.stepId,
        assigneeId: candidate.assigneeId,
        startAt: candidate.startAt,
        endAt: candidate.endAt,
        now: instant,
      );
      for (final phase in phases) {
        try {
          final done = await _attention.runAction<bool>(
            actorUserId: null,
            action: (transaction) => _handle(
              transaction: transaction,
              candidate: candidate,
              phase: phase,
              now: instant,
            ),
          );
          if (done) claimed++;
        } on Object catch (e, st) {
          logger.warning(
            '[PlanStepSweep] ${phase.key} failed: $e',
            e,
            st,
          );
        }
      }
    }
    return claimed;
  }

  Future<bool> _handle({
    required AttentionTransaction transaction,
    required PlanSweepStep candidate,
    required PlanSweepPhase phase,
    required DateTime now,
  }) async {
    final beaconId = candidate.beaconId;
    // Lock order P8: the per-Request lock, status re-read, then the head.
    await _closure.lockRequest(beaconId);
    final request = await _repo.requestInfo(beaconId);
    if (request == null ||
        request.kind != BeaconKind.request ||
        !request.status.isOpenFamily) {
      return false;
    }
    await _repo.lockHead(beaconId);
    final step = await _repo.getStep(candidate.stepId);
    if (step == null ||
        step.isRemoved ||
        step.isDone ||
        step.assigneeId != candidate.assigneeId ||
        step.startAt != candidate.startAt ||
        step.endAt != candidate.endAt) {
      return false;
    }
    if (!await _store.claimSweepMark(key: phase.key, beaconId: beaconId)) {
      return false;
    }
    // Long after its boundary (downtime) a phase still settles state, but
    // without push or email.
    final stale =
        now.difference(phase.boundary) > BeaconPlanConsts.sweepStaleness;
    switch (phase.kind) {
      case PlanSweepPhaseKind.remind:
        await _remind(
          transaction: transaction,
          request: request,
          step: step,
          candidate: candidate,
          phase: phase,
          now: now,
        );
      case PlanSweepPhaseKind.due:
        await _planAttention.reconcile(
          transaction: transaction,
          beaconId: beaconId,
          now: now,
          pushNew: !stale,
        );
        await _repo.touchHead(beaconId);
      case PlanSweepPhaseKind.overdue:
        final assignee = step.assigneeId!;
        final admitted = await _admission.effectiveAdmission(
          beaconId: beaconId,
          viewerId: assignee,
        );
        if (!admitted) break;
        await _record(
          transaction: transaction,
          request: request,
          step: step,
          phase: phase,
          eventType: AttentionEventType.planStepOverdue,
          recipientId: assignee,
          reason: AttentionRecipientReason.planStepAssignee,
          channelEligible: !stale,
        );
      case PlanSweepPhaseKind.authorLate:
        if (request.authorId == step.assigneeId) break;
        await _record(
          transaction: transaction,
          request: request,
          step: step,
          phase: phase,
          eventType: AttentionEventType.planStepLate,
          recipientId: request.authorId,
          reason: AttentionRecipientReason.authorOfBeacon,
          relativeMinutes: now.difference(phase.boundary).inMinutes,
          channelEligible:
              now.difference(
                phase.boundary.add(BeaconPlanConsts.authorLateDelay),
              ) <=
              BeaconPlanConsts.sweepStaleness,
        );
      case PlanSweepPhaseKind.unassignedDue:
        await _record(
          transaction: transaction,
          request: request,
          step: step,
          phase: phase,
          eventType: AttentionEventType.planStepUnassigned,
          recipientId: request.authorId,
          reason: AttentionRecipientReason.authorOfBeacon,
          channelEligible: !stale,
        );
    }
    return true;
  }

  Future<void> _remind({
    required AttentionTransaction transaction,
    required PlanRequestInfo request,
    required PlanStepRecord step,
    required PlanSweepStep candidate,
    required PlanSweepPhase phase,
    required DateTime now,
  }) async {
    final start = step.startAt!;
    final windowOpens = start.subtract(kPlanReminderLead);
    final untilStart = start.difference(now);
    // A reminder that is late, nearly pointless, or about a step that was
    // only just set is not sent at all (plan §4.5).
    if (now.difference(windowOpens) > BeaconPlanConsts.sweepStaleness) return;
    if (untilStart < BeaconPlanConsts.reminderMinLead) return;
    final timedAt = candidate.timedAt;
    if (timedAt != null && timedAt.isAfter(windowOpens)) return;
    final assignee = step.assigneeId!;
    final admitted = await _admission.effectiveAdmission(
      beaconId: request.beaconId,
      viewerId: assignee,
    );
    if (!admitted) return;
    await _record(
      transaction: transaction,
      request: request,
      step: step,
      phase: phase,
      eventType: AttentionEventType.planStepReminder,
      recipientId: assignee,
      reason: AttentionRecipientReason.planStepAssignee,
      relativeMinutes: (untilStart.inSeconds / 60).ceil(),
    );
  }

  Future<void> _record({
    required AttentionTransaction transaction,
    required PlanRequestInfo request,
    required PlanStepRecord step,
    required PlanSweepPhase phase,
    required AttentionEventType eventType,
    required String recipientId,
    required AttentionRecipientReason reason,
    int? relativeMinutes,
    bool channelEligible = true,
  }) async {
    // The claim makes each phase run once; the occurrence key is the same
    // as the claim, so a replay is a no-op rather than a key-reuse error.
    if (await _store.occurrenceExists(phase.key)) return;
    await transaction.record(
      await _intents.planEvent(
        eventType: eventType,
        beaconId: request.beaconId,
        beaconTitle: request.title,
        actorUserId: null,
        recipients: {recipientId: reason},
        sourceEventKey: phase.key,
        stepId: step.id,
        stepTitle: step.title,
        relativeMinutes: relativeMinutes,
        channelEligible: channelEligible,
      ),
    );
  }
}
