import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/plan/plan.dart';

import 'package:tentura_server/consts/beacon_plan_consts.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/beacon_plan.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_command_port.dart';
import 'package:tentura_server/domain/port/beacon_plan_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_notification_context_port.dart';
import 'package:tentura_server/domain/port/closure_repository_port.dart';
import 'package:tentura_server/domain/port/plan_attention_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/utils/id.dart';

import '_use_case_base.dart';

/// Request plan («либретто», #220): attention side effects of plan writes
/// (`plan-implementation.md` §4.6).
///
/// `BeaconPlanCase` calls one hook per write, inside the write's transaction
/// and under the plan lock. Each hook records the optional notices of that
/// write and then [reconcile]s the plan obligations of the Request.
///
/// Obligations (all `requiresAction`, never in For You — owner rule D12):
/// * `planStepDue` / `planStepTurn` — at most one per assignee and Request:
///   the assignee's current step by `PlanSchedule.forViewer`, `Due` when it
///   has a start, `Turn` when it became theirs because the previous step was
///   ticked (or it is the first step).
/// * `planChangePending` — one per person and Request while the «Понятно»
///   ledger says they have unconfirmed changes; renewed by every revision
///   that touches their steps.
///
/// Outside the open family the reconciler opens nothing new: in review it
/// still opens a pending change but ends step obligations (P21); once the
/// Request no longer allows coordination every plan obligation is
/// superseded.
@Singleton(order: 1)
class PlanAttentionCase extends UseCaseBase {
  PlanAttentionCase(
    this._repo,
    this._admission,
    this._store,
    this._intents,
    this._attention,
    this._closure,
    this._context, {
    required super.env,
    required super.logger,
  });

  final BeaconPlanRepositoryPort _repo;

  /// `beacon_effective_admission`: author, steward, accepted helper or
  /// admitted room member, minus blocks.
  final BeaconHierarchyCommandPort _admission;
  final PlanAttentionRepositoryPort _store;
  final AttentionIntentCase _intents;
  final TransactionalAttentionCase _attention;
  final ClosureRepositoryPort _closure;
  final BeaconRoomNotificationContextPort _context;

  Future<bool> _isAdmitted(String beaconId, String userId) =>
      _admission.effectiveAdmission(beaconId: beaconId, viewerId: userId);

  // ---------------------------------------------------------------- hooks

  /// A revision was written (save, restore, «Не успеваю», leave).
  Future<void> afterRevision({
    required AttentionTransaction transaction,
    required PlanRequestInfo request,
    required String? actorId,
    required PlanRevisionRecord revision,
  }) async {
    if (request.status.allowsCoordination) {
      final pendingIds = await _renewPendingChanges(
        transaction: transaction,
        request: request,
        actorId: actorId,
        revision: revision,
      );
      if (revision.kind == PlanRevisionKind.unassignedOnLeave) {
        await _notifyUnassignedOnLeave(
          transaction: transaction,
          request: request,
          actorId: actorId,
          revision: revision,
        );
      }
      await _notifyRoom(
        transaction: transaction,
        request: request,
        actorId: actorId,
        eventType: AttentionEventType.planEdited,
        sourceEventKey: 'plan_edited:${request.beaconId}:${revision.seq}',
        collapseFamily: 'plan_edited',
        skip: pendingIds,
      );
    }
    await reconcile(
      transaction: transaction,
      beaconId: request.beaconId,
      actorId: actorId,
    );
  }

  /// A step was ticked ([done]) or unticked.
  Future<void> afterTick({
    required AttentionTransaction transaction,
    required PlanRequestInfo request,
    required String actorId,
    required PlanStepRecord step,
    required bool done,
  }) async {
    if (done) {
      final head = await _repo.getHead(request.beaconId);
      await _notifyRoom(
        transaction: transaction,
        request: request,
        actorId: actorId,
        eventType: AttentionEventType.planStepDone,
        sourceEventKey:
            'plan_done:${step.id}:${head?.changeSeq ?? 0}:'
            '${generateId('A')}',
        collapseFamily: 'plan_done',
        stepId: step.id,
        stepTitle: step.title,
        skip: {?step.assigneeId},
      );
    }
    await reconcile(
      transaction: transaction,
      beaconId: request.beaconId,
      actorId: actorId,
    );
  }

  /// [userId] confirmed plan changes up to [uptoSeq].
  Future<void> afterAck({
    required AttentionTransaction transaction,
    required PlanRequestInfo request,
    required String userId,
    required int uptoSeq,
  }) => reconcile(
    transaction: transaction,
    beaconId: request.beaconId,
    actorId: userId,
  );

  /// «Не успеваю» by the assignee ([actorId]) of [step]. The caller already
  /// reconciled; this tells the author. [sourceEventKey] is unique per act.
  Future<void> afterCantMake({
    required AttentionTransaction transaction,
    required PlanRequestInfo request,
    required String actorId,
    required PlanStepRecord step,
    required String option,
    required String sourceEventKey,
    String excerpt = '',
  }) async {
    if (request.authorId == actorId) return;
    if (!request.status.allowsCoordination) return;
    await transaction.record(
      await _intents.planEvent(
        eventType: AttentionEventType.planCantMake,
        beaconId: request.beaconId,
        beaconTitle: request.title,
        actorUserId: actorId,
        recipients: {request.authorId: AttentionRecipientReason.authorOfBeacon},
        sourceEventKey: sourceEventKey,
        stepId: step.id,
        stepTitle: step.title,
      ),
    );
  }

  /// A Request changed status (close, review, reopen, cancel, delete): plan
  /// obligations follow (P21). Runs inside the caller's transaction; takes
  /// the per-Request lock (P8). Recording new obligations (reopen) joins the
  /// caller's transaction through [TransactionalAttentionCase.runAction], so
  /// [actorId] must be the actor of that transaction.
  Future<void> onRequestStatusChanged({
    required String beaconId,
    String? actorId,
  }) async {
    await _closure.lockRequest(beaconId);
    final request = await _repo.requestInfo(beaconId);
    if (request == null || request.kind != BeaconKind.request) return;
    if (request.status.isOpenFamily && env.planEnabled) {
      await _attention.runAction<void>(
        actorUserId: actorId,
        action: (transaction) => reconcile(
          transaction: transaction,
          beaconId: beaconId,
          actorId: actorId,
        ),
      );
      return;
    }
    await reconcile(beaconId: beaconId, actorId: actorId);
  }

  // ------------------------------------------------------------ reconcile

  /// Brings the live plan obligations of [beaconId] in line with the plan.
  ///
  /// Settles what is no longer owed (`resolved` when the step was ticked or
  /// the change confirmed, `superseded` otherwise) and records what is owed
  /// but missing. Without a [transaction] it only settles. [pushNew] =
  /// false records new obligations without push or email (a sweep phase
  /// found long after its boundary).
  Future<void> reconcile({
    required String beaconId,
    AttentionTransaction? transaction,
    String? actorId,
    DateTime? now,
    bool pushNew = true,
  }) async {
    final instant = (now ?? DateTime.timestamp()).toUtc();
    final live = await _store.liveObligations(beaconId);
    final request = await _repo.requestInfo(beaconId);
    if (request == null ||
        request.kind != BeaconKind.request ||
        !request.status.allowsCoordination ||
        !env.planEnabled) {
      await _store.settle(
        [for (final o in live) o.receiptId],
        kind: AttentionSettlementKind.superseded,
      );
      return;
    }
    final status = request.status;

    final steps = await _repo.liveSteps(beaconId);
    final stepsById = {for (final s in steps) s.id: s};
    final states = [for (final s in steps) s.state];
    final admitted = <String, bool>{};
    Future<bool> isAdmitted(String userId) async =>
        admitted[userId] ??= await _isAdmitted(beaconId, userId);

    // What each person owes now.
    final wantStep = <String, (String, AttentionEventType)>{};
    if (status.isOpenFamily) {
      final assignees = {for (final s in steps) ?s.assigneeId};
      for (final userId in assignees) {
        if (!await isAdmitted(userId)) continue;
        final current = PlanSchedule.forViewer(userId, states, instant).current;
        if (current == null) continue;
        wantStep[userId] = (
          current.id,
          current.startAt != null
              ? AttentionEventType.planStepDue
              : AttentionEventType.planStepTurn,
        );
      }
    }
    final members = {
      for (final m in await _repo.listMembers(beaconId)) m.userId: m,
    };
    final wantPending = <String>{
      for (final m in members.values)
        if (m.isPending && await isAdmitted(m.userId)) m.userId,
    };

    // Settle what is no longer owed.
    final resolved = <String>[];
    final superseded = <String>[];
    final keptStep = <String>{};
    final keptPending = <String>{};
    for (final o in live) {
      switch (o.eventType) {
        case AttentionEventType.planStepDue || AttentionEventType.planStepTurn:
          final want = wantStep[o.accountId];
          if (want != null &&
              want.$1 == o.stepId &&
              want.$2 == o.eventType &&
              keptStep.add(o.accountId)) {
            continue;
          }
          final step = stepsById[o.stepId];
          if (step != null && step.isDone && step.assigneeId == o.accountId) {
            resolved.add(o.receiptId);
          } else {
            superseded.add(o.receiptId);
          }
        case AttentionEventType.planChangePending:
          if (wantPending.contains(o.accountId) &&
              keptPending.add(o.accountId)) {
            continue;
          }
          final member = members[o.accountId];
          if (member != null &&
              !member.isPending &&
              await isAdmitted(o.accountId)) {
            resolved.add(o.receiptId);
          } else {
            superseded.add(o.receiptId);
          }
        case _:
          superseded.add(o.receiptId);
      }
    }
    await _store.settle(
      resolved,
      kind: AttentionSettlementKind.resolved,
      settledByUserId: actorId,
    );
    await _store.settle(superseded, kind: AttentionSettlementKind.superseded);
    if (transaction == null) return;

    // Record what is owed but missing.
    for (final MapEntry(key: userId, value: (stepId, eventType))
        in wantStep.entries) {
      if (keptStep.contains(userId)) continue;
      final step = stepsById[stepId]!;
      await transaction.record(
        await _intents.planEvent(
          eventType: eventType,
          beaconId: beaconId,
          beaconTitle: request.title,
          actorUserId: null,
          recipients: {userId: AttentionRecipientReason.planStepAssignee},
          sourceEventKey:
              'plan_obl:${eventType.name}:$stepId:$userId:${generateId('A')}',
          stepId: stepId,
          stepTitle: step.title,
          channelEligible: pushNew,
        ),
      );
    }
    final head = await _repo.getHead(beaconId);
    for (final userId in wantPending) {
      if (keptPending.contains(userId)) continue;
      await _recordPending(
        transaction: transaction,
        request: request,
        actorId: null,
        userId: userId,
        seq: head?.revisionSeq ?? 0,
        stepTitle: '',
      );
    }
  }

  // -------------------------------------------------------------- helpers

  /// Every revision that touches someone's steps renews their pending
  /// change (supersede by logical task key). Returns who got one.
  Future<Set<String>> _renewPendingChanges({
    required AttentionTransaction transaction,
    required PlanRequestInfo request,
    required String? actorId,
    required PlanRevisionRecord revision,
  }) async {
    final affected = revision.affectedUserIds..remove(actorId);
    if (affected.isEmpty) return const {};
    final renewed = <String>{};
    for (final userId in affected) {
      final member = await _repo.getMember(request.beaconId, userId);
      if (member == null || !member.isPending) continue;
      if (!await _isAdmitted(request.beaconId, userId)) continue;
      var stepTitle = '';
      for (final c in revision.changes) {
        final op = PlanChangeOp.fromWire(c['op'] as String?);
        if (op == null) continue;
        if (PlanChange.fromJson(c).affectedUserIds.contains(userId)) {
          stepTitle = (c['title'] as String?) ?? '';
          break;
        }
      }
      await _recordPending(
        transaction: transaction,
        request: request,
        actorId: actorId,
        userId: userId,
        seq: revision.seq,
        stepTitle: stepTitle,
      );
      renewed.add(userId);
    }
    return renewed;
  }

  Future<void> _recordPending({
    required AttentionTransaction transaction,
    required PlanRequestInfo request,
    required String? actorId,
    required String userId,
    required int seq,
    required String stepTitle,
  }) async {
    var key = 'plan_rev:${request.beaconId}:$seq:$userId';
    if (await _store.occurrenceExists(key)) {
      key = '$key:${generateId('A')}';
    }
    await transaction.record(
      await _intents.planEvent(
        eventType: AttentionEventType.planChangePending,
        beaconId: request.beaconId,
        beaconTitle: request.title,
        actorUserId: actorId == userId ? null : actorId,
        recipients: {userId: AttentionRecipientReason.planStepAssignee},
        sourceEventKey: key,
        stepTitle: stepTitle,
      ),
    );
  }

  Future<void> _notifyUnassignedOnLeave({
    required AttentionTransaction transaction,
    required PlanRequestInfo request,
    required String? actorId,
    required PlanRevisionRecord revision,
  }) async {
    if (request.authorId == actorId) return;
    String? stepId;
    var stepTitle = '';
    for (final c in revision.changes) {
      if (c['stepId'] case final String id) {
        stepId = id;
        stepTitle = (c['title'] as String?) ?? '';
        break;
      }
    }
    await transaction.record(
      await _intents.planEvent(
        eventType: AttentionEventType.planStepUnassigned,
        beaconId: request.beaconId,
        beaconTitle: request.title,
        actorUserId: actorId,
        recipients: {request.authorId: AttentionRecipientReason.authorOfBeacon},
        sourceEventKey:
            'plan_unassigned_leave:${request.beaconId}:${revision.seq}',
        stepId: stepId,
        stepTitle: stepTitle,
      ),
    );
  }

  /// Ambient notice to the room (author, stewards, admitted members) minus
  /// the actor and [skip]. Never pushed.
  Future<void> _notifyRoom({
    required AttentionTransaction transaction,
    required PlanRequestInfo request,
    required String? actorId,
    required AttentionEventType eventType,
    required String sourceEventKey,
    required String collapseFamily,
    Set<String> skip = const {},
    String? stepId,
    String stepTitle = '',
  }) async {
    final context = await _context.loadContextForBeacon(request.beaconId);
    final recipients = <String, AttentionRecipientReason>{};
    void add(Iterable<String> ids, AttentionRecipientReason reason) {
      for (final id in ids) {
        if (id.isEmpty || id == actorId || skip.contains(id)) continue;
        recipients.putIfAbsent(id, () => reason);
      }
    }

    add([request.authorId], AttentionRecipientReason.authorOfBeacon);
    add(
      context.stewardUserIds,
      AttentionRecipientReason.roomModeratorOrSteward,
    );
    add(context.admittedUserIds, AttentionRecipientReason.admittedRoomMember);
    if (recipients.isEmpty) return;
    await transaction.record(
      await _intents.planEvent(
        eventType: eventType,
        beaconId: request.beaconId,
        beaconTitle: request.title,
        actorUserId: actorId,
        recipients: recipients,
        sourceEventKey: sourceEventKey,
        stepId: stepId,
        stepTitle: stepTitle,
        channelEligible: false,
        collapseFamily: collapseFamily,
      ),
    );
  }
}
