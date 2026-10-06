import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/plan/plan.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/consts/beacon_plan_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/beacon_plan.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_command_port.dart';
import 'package:tentura_server/domain/port/beacon_plan_repository_port.dart';
import 'package:tentura_server/domain/port/closure_repository_port.dart';
import 'package:tentura_server/domain/use_case/plan_attention_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

import '_use_case_base.dart';

/// Request plan («либретто», #220): reads and writes.
///
/// Every write follows one lock order (plan P8): `lockRequest` (shared with
/// close / finalize), then the Request status is re-read, then the
/// `beacon_plan` head row is locked, then steps and room lines are written.
@Singleton(order: 1)
class BeaconPlanCase extends UseCaseBase {
  BeaconPlanCase(
    this._repo,
    this._admission,
    this._closure,
    this._attention,
    this._effects, {
    required super.env,
    required super.logger,
  });

  final BeaconPlanRepositoryPort _repo;

  /// `beacon_effective_admission`: author, steward, accepted helper or
  /// admitted room member, minus blocks.
  final BeaconHierarchyCommandPort _admission;
  final ClosureRepositoryPort _closure;
  final TransactionalAttentionCase _attention;
  final PlanAttentionCase _effects;

  Future<bool> _isAdmitted(String beaconId, String userId) =>
      _admission.effectiveAdmission(beaconId: beaconId, viewerId: userId);

  // ---------------------------------------------------------------- reads

  /// The plan of [beaconId] for [viewerId] (`beaconPlan`).
  Future<Map<String, Object?>> view({
    required String beaconId,
    required String viewerId,
  }) async {
    final request = await _readable(beaconId: beaconId, viewerId: viewerId);
    final head = await _repo.getHead(beaconId);
    final steps = await _repo.liveSteps(beaconId);
    final members = await _repo.listMembers(beaconId);
    final membersById = {for (final m in members) m.userId: m};
    final status = request.status;
    final editable =
        env.planEnabled &&
        (status.allowsCoordination ||
            (status == BeaconStatus.draft && request.authorId == viewerId));
    final tickable = env.planEnabled && status.allowsCoordination;

    final viewerMember = membersById[viewerId];
    Map<String, Object?>? viewerPending;
    if (viewerMember?.pendingFromSeq case final int from?) {
      final revisions = await _repo.listRevisions(
        beaconId,
        afterSeq: from - 1,
        limit: 200,
      );
      final changes = <Map<String, Object?>>[];
      final actorIds = <String>{};
      for (final r in revisions.reversed) {
        if (r.actorId == viewerId) continue;
        for (final c in r.changes) {
          final op = PlanChangeOp.fromWire(c['op'] as String?);
          if (op == null) continue;
          if (PlanChange.fromJson(c).affectedUserIds.contains(viewerId)) {
            changes.add({...c, 'seq': r.seq});
            if (r.actorId != null) actorIds.add(r.actorId!);
          }
        }
      }
      viewerPending = {
        'fromSeq': from,
        'headSeq': head?.revisionSeq ?? 0,
        'changes': changes,
        'actorIds': actorIds.toList(),
      };
    }

    final userIds = <String>{
      for (final s in steps) ...{?s.assigneeId, ?s.doneById},
      ?head?.lastEditedById,
      ...?(viewerPending?['actorIds'] as List<String>?),
    };
    final names = await _repo.displayNames(userIds);
    final copiedFrom = head?.copiedFromBeaconId;
    String? copiedFromTitle;
    if (copiedFrom != null && await _isAdmitted(copiedFrom, viewerId)) {
      copiedFromTitle = (await _repo.requestInfo(copiedFrom))?.title;
    }

    return {
      'beaconId': beaconId,
      'revisionSeq': head?.revisionSeq ?? 0,
      'changeSeq': head?.changeSeq ?? 0,
      'lastEditedById': head?.lastEditedById,
      'lastEditedAt': head?.lastEditedAt?.toIso8601String(),
      'copiedFromBeaconId': copiedFrom,
      'copiedFromTitle': copiedFromTitle,
      'editable': editable,
      'tickable': tickable,
      'steps': [
        for (final (i, s) in steps.indexed)
          {
            'id': s.id,
            'index': i + 1,
            'title': s.title,
            'description': s.description,
            'assigneeId': s.assigneeId,
            'startAt': formatPlanInstant(s.startAt),
            'endAt': formatPlanInstant(s.endAt),
            'doneAt': formatPlanInstant(s.doneAt),
            'doneById': s.doneById,
            'contentSeq': s.contentSeq,
            'ackSeq': s.ackSeq,
            'assigneeAckPending': _ackPending(s, membersById),
          },
      ],
      'members': [
        for (final m in members)
          {'userId': m.userId, 'ackedAt': m.ackedAt?.toIso8601String()},
      ],
      'viewerPending': viewerPending,
      'names': names,
    };
  }

  /// My Work / inbox plan slices (`planSliceJson`, plan §4.9) of [viewerId]
  /// for [beaconIds], keyed by beacon id. One batched read for all of them.
  ///
  /// A Request without steps and without pending changes has no slice, and
  /// neither has one outside the coordination statuses, so a finished
  /// Request never offers «Готово» the server would refuse.
  ///
  /// The caller must have checked that [viewerId] may read each Request.
  Future<Map<String, Map<String, Object?>>> slicesFor({
    required String viewerId,
    required Iterable<String> beaconIds,
    DateTime? now,
  }) async {
    if (!env.planEnabled) return const {};
    final ids = beaconIds.toList();
    if (ids.isEmpty) return const {};
    return slicesFrom(
      sources: await _repo.sliceSourcesFor(viewerId, ids),
      viewerId: viewerId,
      now: now,
    );
  }

  /// [buildPlanSlice] over already-read [sources], keyed by beacon id.
  static Map<String, Map<String, Object?>> slicesFrom({
    required Map<String, PlanSliceSource> sources,
    required String viewerId,
    DateTime? now,
  }) {
    final at = (now ?? DateTime.now()).toUtc();
    return {
      for (final source in sources.values)
        source.beaconId: ?buildPlanSlice(
          source: source,
          viewerId: viewerId,
          now: at,
        ),
    };
  }

  /// One `planSliceJson` object (plan §4.9); null when there is nothing to
  /// show.
  static Map<String, Object?>? buildPlanSlice({
    required PlanSliceSource source,
    required String viewerId,
    required DateTime now,
  }) {
    if (!source.status.allowsCoordination) return null;
    final states = [for (final s in source.steps) s.state];
    final pendingAck = _slicePendingAck(source, viewerId);
    if (states.isEmpty && pendingAck == null) return null;
    final byId = {for (final s in source.steps) s.id: s};
    final schedule = PlanSchedule.forViewer(viewerId, states, now);
    final current = schedule.current;
    final next = schedule.next;
    return {
      'current': current == null
          ? null
          : {
              'stepId': current.id,
              'title': current.title,
              'description': byId[current.id]?.description ?? '',
              'startAt': formatPlanInstant(current.startAt),
              'endAt': formatPlanInstant(current.endAt),
            },
      'alsoActive': [
        for (final s in schedule.alsoActive)
          {
            'stepId': s.id,
            'title': s.title,
            'startAt': formatPlanInstant(s.startAt),
            'endAt': formatPlanInstant(s.endAt),
          },
      ],
      'next': next == null
          ? null
          : {
              'stepId': next.id,
              'title': next.title,
              'startAt': formatPlanInstant(next.startAt),
              'endAt': formatPlanInstant(next.endAt),
            },
      'pendingAck': pendingAck,
    };
  }

  /// Changes by others to the viewer's own steps since `pending_from_seq`
  /// (the same filter as [view]'s `viewerPending`).
  static Map<String, Object?>? _slicePendingAck(
    PlanSliceSource source,
    String viewerId,
  ) {
    final from = source.pendingFromSeq;
    if (from == null) return null;
    final relevant = <Map<String, Object?>>[];
    final actorIds = <String>{};
    final actorNames = <String, String>{};
    final stepIds = <String>{};
    DateTime? lastAt;
    for (final r in source.pendingRevisions) {
      if (r.seq < from || r.actorId == viewerId) continue;
      for (final c in r.changes) {
        if (PlanChangeOp.fromWire(c['op'] as String?) == null) continue;
        final change = PlanChange.fromJson(c);
        if (!change.affectedUserIds.contains(viewerId)) continue;
        relevant.add(c);
        stepIds.add(change.stepId);
        if (r.actorId case final String actor) {
          actorIds.add(actor);
          if (r.actorName case final String name when name.trim().isNotEmpty) {
            actorNames[actor] = name.trim();
          }
        }
        lastAt = r.createdAt;
      }
    }
    if (relevant.isEmpty) return null;
    return {
      'fromSeq': from,
      'headSeq': source.revisionSeq,
      'changeCount': relevant.length,
      'actorIds': actorIds.toList(),
      'actorNames': actorNames,
      'stepIds': stepIds.toList(),
      'lastAt': lastAt?.toUtc().toIso8601String(),
      // The newest raw change, so a client can word it like the Plan tab.
      'sample': relevant.last,
    };
  }

  static bool _ackPending(
    PlanStepRecord step,
    Map<String, PlanMemberRecord> members,
  ) {
    final assignee = step.assigneeId;
    if (assignee == null) return false;
    final member = members[assignee];
    final pendingFrom = member?.pendingFromSeq;
    return pendingFrom != null && pendingFrom <= step.ackSeq;
  }

  /// Revision history, newest first (`beaconPlanRevisions`).
  Future<Map<String, Object?>> revisions({
    required String beaconId,
    required String viewerId,
    int? beforeSeq,
    int limit = 30,
  }) async {
    await _readable(beaconId: beaconId, viewerId: viewerId);
    final page = await _repo.listRevisions(
      beaconId,
      beforeSeq: beforeSeq,
      limit: limit + 1,
    );
    final items = page.take(limit).toList();
    final names = await _repo.displayNames({
      for (final r in items) ?r.actorId,
      for (final r in items)
        for (final c in r.changes) ...{
          if (c['fromAssigneeId'] case final String id) id,
          if (c['toAssigneeId'] case final String id) id,
        },
    });
    return {
      'items': [
        for (final r in items)
          {
            'seq': r.seq,
            'kind': r.kind,
            'actorId': r.actorId,
            'comment': r.comment,
            'restoredFromSeq': r.restoredFromSeq,
            'changes': r.changes,
            'createdAt': r.createdAt.toIso8601String(),
          },
      ],
      'names': names,
      'nextBeforeSeq': page.length > limit ? items.last.seq : null,
    };
  }

  /// One revision snapshot (`beaconPlanRevision`).
  Future<Map<String, Object?>> revision({
    required String beaconId,
    required String viewerId,
    required int seq,
  }) async {
    await _readable(beaconId: beaconId, viewerId: viewerId);
    final r =
        await _repo.getRevision(beaconId, seq) ??
        (throw const PlanRestoreSourceMissingException());
    return {
      'seq': r.seq,
      'kind': r.kind,
      'steps': r.snapshot.toJson(),
      'createdAt': r.createdAt.toIso8601String(),
    };
  }

  Future<PlanRequestInfo> _readable({
    required String beaconId,
    required String viewerId,
  }) async {
    final request = await _repo.requestInfo(beaconId);
    if (request == null || request.kind != BeaconKind.request) {
      throw const BeaconNotRequestException();
    }
    if (request.status == BeaconStatus.deleted ||
        !await _isAdmitted(beaconId, viewerId)) {
      throw const UnauthorizedException(description: 'Room access required');
    }
    return request;
  }

  // --------------------------------------------------------------- writes

  /// Saves the caller's draft as a new revision, merging by step with what
  /// others saved since [baseSeq].
  Future<PlanSaveOutcome> save({
    required String actorId,
    required String beaconId,
    required int baseSeq,
    required String stepsJson,
    String comment = '',
  }) {
    final draft = _parseDraft(stepsJson);
    _validateComment(comment);
    return _attention.runAction(
      actorUserId: actorId,
      action: (transaction) async {
        final request = await _preflight(
          beaconId: beaconId,
          actorId: actorId,
          allowDraft: true,
        );
        await _rateLimit(actorId);
        final head = await _repo.lockHead(beaconId);
        final theirs = await _currentSnapshot(beaconId);

        var merged = draft;
        var theirStepIds = const <String>{};
        if (head.revisionSeq != baseSeq) {
          if (baseSeq > head.revisionSeq || baseSeq < 0) {
            throw PlanEditConflictException(currentSeq: head.revisionSeq);
          }
          final base = baseSeq == 0
              ? PlanSnapshot.empty
              : (await _repo.getRevision(beaconId, baseSeq))?.snapshot ??
                    (throw PlanEditConflictException(
                      currentSeq: head.revisionSeq,
                    ));
          switch (PlanMerge.threeWay(base, theirs, draft)) {
            case PlanMergeConflict(:final stepIds):
              throw PlanEditConflictException(
                currentSeq: head.revisionSeq,
                conflictStepIds: stepIds,
              );
            case PlanMergeMerged(:final snapshot, :final theirChangedStepIds):
              merged = snapshot;
              theirStepIds = theirChangedStepIds;
          }
        }
        if (merged.length > BeaconPlanConsts.maxSteps) {
          throw const PlanTooLargeException();
        }
        if (merged.sameAs(theirs)) {
          return PlanSaveOutcome(
            kind: PlanSaveOutcomeKind.noop,
            revisionSeq: head.revisionSeq,
          );
        }
        await _checkNewIds(beaconId, merged, theirs);
        await _checkAssignees(beaconId, merged, theirs);

        final seq = head.revisionSeq + 1;
        final revision = await _writeRevision(
          request: request,
          actorId: actorId,
          seq: seq,
          baseSeq: baseSeq,
          kind: head.revisionSeq == 0
              ? PlanRevisionKind.created
              : PlanRevisionKind.edited,
          from: theirs,
          to: merged,
          comment: comment,
        );
        await _effects.afterRevision(
          transaction: transaction,
          request: request,
          actorId: actorId,
          revision: revision,
        );

        final theirActorIds = <String>{};
        if (head.revisionSeq != baseSeq) {
          final between = await _repo.listRevisions(
            beaconId,
            afterSeq: baseSeq,
            limit: 200,
          );
          for (final r in between) {
            if (r.seq <= head.revisionSeq && r.actorId != null) {
              theirActorIds.add(r.actorId!);
            }
          }
          theirActorIds.remove(actorId);
        }
        return PlanSaveOutcome(
          kind: head.revisionSeq == baseSeq
              ? PlanSaveOutcomeKind.applied
              : PlanSaveOutcomeKind.merged,
          revisionSeq: seq,
          theirStepIds: theirStepIds,
          theirActorIds: theirActorIds,
        );
      },
    );
  }

  /// Makes revision [fromSeq] the current plan (strict CAS on [baseSeq]).
  /// Ticks stay as they are now.
  Future<PlanSaveOutcome> restore({
    required String actorId,
    required String beaconId,
    required int fromSeq,
    required int baseSeq,
  }) => _attention.runAction(
    actorUserId: actorId,
    action: (transaction) async {
      final request = await _preflight(
        beaconId: beaconId,
        actorId: actorId,
        allowDraft: true,
      );
      await _rateLimit(actorId);
      final head = await _repo.lockHead(beaconId);
      if (head.revisionSeq != baseSeq) {
        throw PlanEditConflictException(currentSeq: head.revisionSeq);
      }
      final source =
          await _repo.getRevision(beaconId, fromSeq) ??
          (throw const PlanRestoreSourceMissingException());
      final theirs = await _currentSnapshot(beaconId);
      // People who are no longer admitted cannot get their steps back.
      final restored = PlanSnapshot([
        for (final s in source.snapshot.steps)
          if (s.assigneeId case final String id
              when !await _isAdmitted(beaconId, id))
            s.copyWith(assigneeId: () => null)
          else
            s,
      ]);
      if (restored.sameAs(theirs)) {
        return PlanSaveOutcome(
          kind: PlanSaveOutcomeKind.noop,
          revisionSeq: head.revisionSeq,
        );
      }
      final seq = head.revisionSeq + 1;
      final revision = await _writeRevision(
        request: request,
        actorId: actorId,
        seq: seq,
        baseSeq: baseSeq,
        kind: PlanRevisionKind.restored,
        restoredFromSeq: fromSeq,
        from: theirs,
        to: restored,
      );
      await _effects.afterRevision(
        transaction: transaction,
        request: request,
        actorId: actorId,
        revision: revision,
      );
      return PlanSaveOutcome(
        kind: PlanSaveOutcomeKind.applied,
        revisionSeq: seq,
      );
    },
  );

  /// Ticks ([done]) or unticks a step. Any admitted member may do it.
  Future<void> setDone({
    required String actorId,
    required String stepId,
    required bool done,
  }) => _attention.runAction(
    actorUserId: actorId,
    action: (transaction) async {
      final found =
          await _repo.getStep(stepId) ??
          (throw const PlanStepNotFoundException());
      final request = await _preflight(
        beaconId: found.beaconId,
        actorId: actorId,
      );
      await _repo.lockHead(found.beaconId);
      final step = await _repo.getStep(stepId);
      if (step == null || step.isRemoved) {
        throw const PlanStepNotFoundException();
      }
      final changed = done
          ? await _repo.setDone(stepId: stepId, actorId: actorId)
          : await _repo.clearDone(stepId);
      if (!changed) return;
      await _repo.touchHead(step.beaconId);
      if (done) {
        await _appendTickLine(step: step, actorId: actorId);
        await _repo.insertActivity(
          beaconId: step.beaconId,
          type: BeaconActivityEventTypeBits.planStepDone,
          actorId: actorId,
          stepId: step.id,
          targetUserId: step.assigneeId,
          diff: {'title': step.title},
        );
      } else {
        await _markTickUndone(step: step, actorId: actorId);
      }
      await _effects.afterTick(
        transaction: transaction,
        request: request,
        actorId: actorId,
        step: (await _repo.getStep(stepId))!,
        done: done,
      );
    },
  );

  /// «Понятно»: the caller confirms plan changes up to [uptoSeq].
  Future<void> ack({
    required String actorId,
    required String beaconId,
    required int uptoSeq,
  }) => _attention.runAction(
    actorUserId: actorId,
    action: (transaction) async {
      final request = await _preflight(beaconId: beaconId, actorId: actorId);
      final head = await _repo.lockHead(beaconId);
      final upto = uptoSeq.clamp(0, head.revisionSeq);
      // Oldest first, one seq window at a time: a single newest-first page
      // would skip the earliest revisions after [upto] on long histories.
      const window = 500;
      int? nextPending;
      for (
        var from = upto;
        nextPending == null && from < head.revisionSeq;
        from += window
      ) {
        final later = await _repo.listRevisions(
          beaconId,
          afterSeq: from,
          beforeSeq: from + window + 1,
          limit: window,
        );
        for (final r in later.reversed) {
          if (r.actorId != actorId && r.affectedUserIds.contains(actorId)) {
            nextPending = r.seq;
            break;
          }
        }
      }
      await _repo.writeAck(
        beaconId: beaconId,
        userId: actorId,
        ackedSeq: upto,
        pendingFromSeq: nextPending,
      );
      await _repo.touchHead(beaconId);
      await _effects.afterAck(
        transaction: transaction,
        request: request,
        userId: actorId,
        uptoSeq: upto,
      );
    },
  );

  /// «Не успеваю» by the step's assignee: move it ([newStartAt] /
  /// [newEndAt]) or hand it over ([toUserId]) — a revision each — or say so
  /// in the discussion ([excerpt], option `chat`), which leaves the plan and
  /// its revision counter as they are.
  Future<PlanSaveOutcome> cantMake({
    required String actorId,
    required String stepId,
    required String option,
    required int baseSeq,
    DateTime? newStartAt,
    DateTime? newEndAt,
    String? toUserId,
    String excerpt = '',
  }) => _attention.runAction(
    actorUserId: actorId,
    action: (transaction) async {
      final found =
          await _repo.getStep(stepId) ??
          (throw const PlanStepNotFoundException());
      final beaconId = found.beaconId;
      final request = await _preflight(beaconId: beaconId, actorId: actorId);
      final head = await _repo.lockHead(beaconId);
      final step = (await _repo.getStep(stepId))!;
      if (step.isRemoved || step.assigneeId != actorId) {
        throw const PlanActionStaleException();
      }
      if (step.contentSeq > baseSeq) {
        throw const PlanActionStaleException();
      }
      if (option == PlanCantMakeOption.chat) {
        return _cantMakeChat(
          transaction: transaction,
          request: request,
          head: head,
          step: step,
          actorId: actorId,
          excerpt: excerpt,
        );
      }
      final theirs = await _currentSnapshot(beaconId);
      final seq = head.revisionSeq + 1;
      final PlanSnapshot changed;
      switch (option) {
        case PlanCantMakeOption.reschedule:
          if (newStartAt == null && newEndAt == null) {
            throw const PlanActionStaleException(
              description: 'A new time is required',
            );
          }
          changed = PlanSnapshot([
            for (final s in theirs.steps)
              if (s.id == stepId)
                s.copyWith(
                  startAt: () => newStartAt?.toUtc(),
                  endAt: () => newEndAt?.toUtc(),
                )
              else
                s,
          ]);
          _validateSnapshot(changed);
        case PlanCantMakeOption.handover:
          if (toUserId == null ||
              toUserId == actorId ||
              !await _isAdmitted(beaconId, toUserId)) {
            throw const PlanAssigneeNotAdmittedException();
          }
          changed = PlanSnapshot([
            for (final s in theirs.steps)
              if (s.id == stepId) s.copyWith(assigneeId: () => toUserId) else s,
          ]);
        default:
          throw const PlanActionStaleException(description: 'Unknown option');
      }
      final revision = await _writeRevision(
        request: request,
        actorId: actorId,
        seq: seq,
        baseSeq: head.revisionSeq,
        kind: PlanRevisionKind.cantMake,
        from: theirs,
        to: changed,
        line: false,
      );
      await _repo.insertPlanLine(
        beaconId: beaconId,
        actorId: actorId,
        marker: BeaconRoomSemanticMarker.planCantMake,
        payload: {
          'actorId': actorId,
          'stepId': step.id,
          'title': step.title,
          'option': option,
          'revisionSeq': seq,
          if (option == PlanCantMakeOption.reschedule) ...{
            'fromStartAt': formatPlanInstant(step.startAt),
            'toStartAt': formatPlanInstant(newStartAt),
            'fromEndAt': formatPlanInstant(step.endAt),
            'toEndAt': formatPlanInstant(newEndAt),
          },
          if (option == PlanCantMakeOption.handover) 'toUserId': toUserId,
        },
      );
      await _repo.insertActivity(
        beaconId: beaconId,
        type: BeaconActivityEventTypeBits.planCantMake,
        actorId: actorId,
        stepId: step.id,
        targetUserId: toUserId,
        diff: {'option': option, 'title': step.title, 'revisionSeq': seq},
      );
      // Saying «Не успеваю» is a domain act: it settles the caller's own
      // pending confirmation (request-attention §5).
      await _repo.clearPending(beaconId, actorId);
      await _effects.afterRevision(
        transaction: transaction,
        request: request,
        actorId: actorId,
        revision: revision,
      );
      await _effects.afterCantMake(
        transaction: transaction,
        request: request,
        actorId: actorId,
        step: step,
        option: option,
        sourceEventKey: 'plan_cant_make:$beaconId:$seq',
        excerpt: excerpt,
      );
      return PlanSaveOutcome(
        kind: PlanSaveOutcomeKind.applied,
        revisionSeq: seq,
      );
    },
  );

  /// «Не успеваю → обсуждение»: the person's own words go to the discussion
  /// (the client sends them); here only the activity, the settled pending
  /// confirmation and the author's notice are recorded. No revision: the
  /// plan did not change, so concurrent editors and restores are unaffected.
  Future<PlanSaveOutcome> _cantMakeChat({
    required AttentionTransaction transaction,
    required PlanRequestInfo request,
    required BeaconPlanHead head,
    required PlanStepRecord step,
    required String actorId,
    required String excerpt,
  }) async {
    final beaconId = request.beaconId;
    await _repo.insertActivity(
      beaconId: beaconId,
      type: BeaconActivityEventTypeBits.planCantMake,
      actorId: actorId,
      stepId: step.id,
      diff: {'option': PlanCantMakeOption.chat, 'title': step.title},
    );
    // Saying «Не успеваю» is a domain act: it settles the caller's own
    // pending confirmation (request-attention §5).
    await _repo.clearPending(beaconId, actorId);
    // `change_seq` only (realtime refresh); `revision_seq` stays.
    await _repo.touchHead(beaconId);
    await _effects.reconcile(
      transaction: transaction,
      beaconId: beaconId,
      actorId: actorId,
    );
    await _effects.afterCantMake(
      transaction: transaction,
      request: request,
      actorId: actorId,
      step: step,
      option: PlanCantMakeOption.chat,
      sourceEventKey:
          'plan_cant_make:$beaconId:chat:${step.id}:${head.changeSeq + 1}',
      excerpt: excerpt,
    );
    return PlanSaveOutcome(
      kind: PlanSaveOutcomeKind.applied,
      revisionSeq: head.revisionSeq,
    );
  }

  /// Removes [userId] as assignee from every live step of [beaconId] (they
  /// left the room, were removed or blocked). Runs inside the caller's
  /// transaction; writes one `unassigned_on_leave` revision when anything
  /// changed. Someone who is still admitted (a steward, the author) keeps
  /// their steps.
  Future<void> unassignOnLeave({
    required AttentionTransaction transaction,
    required String beaconId,
    required String userId,
    String? actorId,
  }) async {
    if (!env.planEnabled) return;
    final request = await _repo.requestInfo(beaconId);
    if (request == null || request.kind != BeaconKind.request) return;
    final head = await _repo.getHead(beaconId);
    if (head == null) return;
    await _closure.lockRequest(beaconId);
    if (await _isAdmitted(beaconId, userId)) return;
    final locked = await _repo.lockHead(beaconId);
    final theirs = await _currentSnapshot(beaconId);
    if (!theirs.steps.any((s) => s.assigneeId == userId)) return;
    final freed = PlanSnapshot([
      for (final s in theirs.steps)
        if (s.assigneeId == userId) s.copyWith(assigneeId: () => null) else s,
    ]);
    final revision = await _writeRevision(
      request: request,
      actorId: actorId,
      seq: locked.revisionSeq + 1,
      baseSeq: locked.revisionSeq,
      kind: PlanRevisionKind.unassignedOnLeave,
      from: theirs,
      to: freed,
      subjectUserId: userId,
    );
    await _repo.clearPending(beaconId, userId);
    await _effects.afterRevision(
      transaction: transaction,
      request: request,
      actorId: actorId,
      revision: revision,
    );
  }

  /// Copies the live plan of [sourceBeaconId] into the fresh draft
  /// [targetBeaconId] (fork). Assignments are reset; times come from
  /// [stepTimes] (source step id → new start/end) and default to none.
  /// Runs inside the fork's transaction. Returns the number of steps copied.
  Future<int> copyPlan({
    required String actorId,
    required String sourceBeaconId,
    required String targetBeaconId,
    Map<String, ({DateTime? startAt, DateTime? endAt})> stepTimes = const {},
  }) async {
    if (!env.planEnabled) return 0;
    if (!await _isAdmitted(sourceBeaconId, actorId)) return 0;
    final source = await _repo.liveSteps(sourceBeaconId);
    if (source.isEmpty) return 0;
    final head = await _repo.lockHead(targetBeaconId);
    if (head.revisionSeq != 0) return 0;
    final steps = <PlanStepSnapshot>[];
    for (final s in source) {
      final times = stepTimes[s.id];
      var start = times?.startAt?.toUtc();
      var end = times?.endAt?.toUtc();
      if (start != null && end != null && end.isBefore(start)) end = null;
      if (times == null) {
        start = null;
        end = null;
      }
      steps.add(
        PlanStepSnapshot(
          id: newPlanStepId(),
          title: s.title,
          description: s.description,
          startAt: start,
          endAt: end,
        ),
      );
    }
    final snapshot = PlanSnapshot(steps);
    await _repo.insertRevision(
      beaconId: targetBeaconId,
      seq: 1,
      baseSeq: 0,
      kind: PlanRevisionKind.copied,
      actorId: actorId,
      snapshot: snapshot,
      changes: [
        for (final c in PlanDiff.between(PlanSnapshot.empty, snapshot))
          c.toJson(),
      ],
    );
    await _repo.writeSteps(
      beaconId: targetBeaconId,
      seq: 1,
      actorId: actorId,
      snapshot: snapshot,
      ackChangedIds: const {},
    );
    await _repo.touchHead(targetBeaconId, revisionSeq: 1, editedById: actorId);
    await _repo.setCopiedFrom(
      beaconId: targetBeaconId,
      sourceBeaconId: sourceBeaconId,
    );
    return steps.length;
  }

  /// On publish of a Request that carries a plan: plan obligations start
  /// (the author's own steps, a first untimed step), and a fork copy gets
  /// the «План скопирован» line (marker 16). Runs inside the publish
  /// transaction.
  Future<void> onPublished({
    required AttentionTransaction transaction,
    required String beaconId,
    required String actorId,
  }) async {
    if (!env.planEnabled) return;
    final existing = await _repo.getHead(beaconId);
    if (existing == null) return;
    await _closure.lockRequest(beaconId);
    final head = await _repo.lockHead(beaconId);
    await _effects.reconcile(
      transaction: transaction,
      beaconId: beaconId,
      actorId: actorId,
    );
    final source = head.copiedFromBeaconId;
    if (source == null) return;
    final steps = await _repo.liveSteps(beaconId);
    if (steps.isEmpty) return;
    await _repo.insertPlanLine(
      beaconId: beaconId,
      actorId: actorId,
      marker: BeaconRoomSemanticMarker.planCopied,
      payload: {
        'sourceBeaconId': source,
        'stepCount': steps.length,
        'revisionSeq': head.revisionSeq,
      },
    );
    await _repo.insertActivity(
      beaconId: beaconId,
      type: BeaconActivityEventTypeBits.planCopied,
      actorId: actorId,
      diff: {'sourceBeaconId': source, 'stepCount': steps.length},
    );
    await _repo.touchHead(beaconId);
  }

  // -------------------------------------------------------------- helpers

  Future<PlanRequestInfo> _preflight({
    required String beaconId,
    required String actorId,
    bool allowDraft = false,
  }) async {
    if (!env.planEnabled) throw const PlanDisabledException();
    final first = await _repo.requestInfo(beaconId);
    if (first == null || first.kind != BeaconKind.request) {
      throw const BeaconNotRequestException();
    }
    await _closure.lockRequest(beaconId);
    final request = (await _repo.requestInfo(beaconId))!;
    final status = request.status;
    final draftOk =
        allowDraft &&
        status == BeaconStatus.draft &&
        request.authorId == actorId;
    if (!status.allowsCoordination && !draftOk) {
      throw const PlanNotEditableException();
    }
    if (!await _isAdmitted(beaconId, actorId)) {
      throw const UnauthorizedException(description: 'Room access required');
    }
    return request;
  }

  Future<void> _rateLimit(String actorId) async {
    final recent = await _repo.countRevisionsByActorSince(
      actorId,
      DateTime.timestamp().subtract(BeaconPlanConsts.rateWindow),
    );
    if (recent >= BeaconPlanConsts.rateMax) {
      throw const PlanRateLimitedException();
    }
  }

  Future<PlanSnapshot> _currentSnapshot(String beaconId) async => PlanSnapshot([
    for (final s in await _repo.liveSteps(beaconId)) s.snapshot,
  ]);

  Future<void> _checkNewIds(
    String beaconId,
    PlanSnapshot merged,
    PlanSnapshot theirs,
  ) async {
    final known = theirs.ids.toSet();
    final fresh = merged.ids.where((id) => !known.contains(id)).toList();
    for (final id in fresh) {
      if (!BeaconPlanConsts.stepIdPattern.hasMatch(id)) {
        throw const PlanActionStaleException(description: 'Bad step id');
      }
    }
    if ((await _repo.foreignStepIds(beaconId, fresh)).isNotEmpty) {
      throw const PlanActionStaleException(description: 'Step id is taken');
    }
  }

  /// Only admitted people can be given a step. An assignee who stays as is
  /// (even if they left meanwhile) is not re-checked.
  Future<void> _checkAssignees(
    String beaconId,
    PlanSnapshot merged,
    PlanSnapshot theirs,
  ) async {
    final before = theirs.byId;
    final checked = <String>{};
    for (final s in merged.steps) {
      final who = s.assigneeId;
      if (who == null || before[s.id]?.assigneeId == who) continue;
      if (!checked.add(who)) continue;
      if (!await _isAdmitted(beaconId, who)) {
        throw const PlanAssigneeNotAdmittedException();
      }
    }
  }

  Future<PlanRevisionRecord> _writeRevision({
    required PlanRequestInfo request,
    required String? actorId,
    required int seq,
    required int baseSeq,
    required int kind,
    required PlanSnapshot from,
    required PlanSnapshot to,
    int? restoredFromSeq,
    String comment = '',
    String? subjectUserId,
    bool line = true,
  }) async {
    final beaconId = request.beaconId;
    final changes = PlanDiff.between(from, to);
    final changesJson = [for (final c in changes) c.toJson()];
    await _repo.insertRevision(
      beaconId: beaconId,
      seq: seq,
      baseSeq: baseSeq,
      kind: kind,
      actorId: actorId,
      restoredFromSeq: restoredFromSeq,
      snapshot: to,
      changes: changesJson,
      comment: comment.trim(),
    );
    await _repo.writeSteps(
      beaconId: beaconId,
      seq: seq,
      actorId: actorId,
      snapshot: to,
      ackChangedIds: {
        for (final c in changes)
          if (c.op.needsAck) c.stepId,
      },
    );
    await _repo.touchHead(beaconId, revisionSeq: seq, editedById: actorId);
    final affected = PlanDiff.affectedUserIds(changes)..remove(actorId);
    await _repo.markPending(beaconId, affected, seq);
    if (line) {
      final messageId = await _repo.insertPlanLine(
        beaconId: beaconId,
        actorId: actorId,
        marker: BeaconRoomSemanticMarker.planRevised,
        payload: {
          'actorId': ?actorId,
          'revisionSeq': seq,
          'revisionKind': kind,
          'restoredFromSeq': ?restoredFromSeq,
          'changeCount': changes.length,
          'changes': changesJson
              .take(BeaconPlanConsts.systemLineMaxEntries)
              .toList(),
          'comment': comment.trim(),
          'subjectUserId': ?subjectUserId,
        },
      );
      await _repo.insertActivity(
        beaconId: beaconId,
        type: BeaconActivityEventTypeBits.planRevised,
        actorId: actorId,
        targetUserId: subjectUserId,
        sourceMessageId: messageId,
        diff: {
          'revisionSeq': seq,
          'revisionKind': kind,
          'changeCount': changes.length,
        },
      );
    }
    return (await _repo.getRevision(beaconId, seq))!;
  }

  /// Marker-14 coalescing (plan P12): ticks within 30 minutes of the tail
  /// line join it; anything else in between starts a new line.
  Future<void> _appendTickLine({
    required PlanStepRecord step,
    required String actorId,
  }) async {
    final entry = <String, Object?>{
      'stepId': step.id,
      'title': step.title,
      'assigneeId': step.assigneeId,
      'actorId': actorId,
      'at': DateTime.timestamp().toIso8601String(),
    };
    final tail = await _repo.tailMainRoomMessage(step.beaconId);
    final ticks = tail?.payload?['ticks'];
    if (tail != null &&
        tail.marker == BeaconRoomSemanticMarker.planStepsDone &&
        DateTime.timestamp().difference(tail.createdAt) <
            BeaconPlanConsts.tickCoalesceWindow &&
        ticks is List &&
        ticks.length < BeaconPlanConsts.systemLineMaxEntries) {
      await _repo.updateLinePayload(tail.id, {
        ...?tail.payload,
        'ticks': [...ticks, entry],
      });
      return;
    }
    await _repo.insertPlanLine(
      beaconId: step.beaconId,
      actorId: actorId,
      marker: BeaconRoomSemanticMarker.planStepsDone,
      payload: {
        'ticks': [entry],
      },
    );
  }

  /// Untick (plan P17): the chat line stays; its entry is struck through.
  Future<void> _markTickUndone({
    required PlanStepRecord step,
    required String actorId,
  }) async {
    final line = await _repo.latestTickLineFor(step.beaconId, step.id);
    final ticks = line?.payload?['ticks'];
    if (line == null || ticks is! List) return;
    final updated = [...ticks];
    for (var i = updated.length - 1; i >= 0; i--) {
      final t = updated[i];
      if (t is Map && t['stepId'] == step.id && t['undoneAt'] == null) {
        updated[i] = {
          ...t.cast<String, Object?>(),
          'undoneAt': DateTime.timestamp().toIso8601String(),
          'undoneById': actorId,
        };
        break;
      }
    }
    await _repo.updateLinePayload(line.id, {
      ...?line.payload,
      'ticks': updated,
    });
  }

  static PlanSnapshot _parseDraft(String stepsJson) {
    final PlanSnapshot draft;
    try {
      draft = PlanSnapshot.fromJson(stepsJson);
    } on Object {
      throw const PlanInvalidException(description: 'Malformed plan');
    }
    _validateSnapshot(draft);
    return draft;
  }

  static void _validateSnapshot(PlanSnapshot draft) {
    if (draft.length > BeaconPlanConsts.maxSteps) {
      throw const PlanTooLargeException();
    }
    final seen = <String>{};
    for (final s in draft.steps) {
      if (!seen.add(s.id)) {
        throw const PlanInvalidException(description: 'Duplicate step id');
      }
      final title = s.title.trim();
      if (title.isEmpty || title.length > BeaconPlanConsts.maxTitleLength) {
        throw const PlanInvalidException(description: 'Bad step title');
      }
      if (s.description.length > BeaconPlanConsts.maxDescriptionLength) {
        throw const PlanTooLargeException(description: 'Description too long');
      }
      final start = s.startAt;
      final end = s.endAt;
      if (start != null && end != null && end.isBefore(start)) {
        throw const PlanInvalidException(description: 'End before start');
      }
    }
  }

  static void _validateComment(String comment) {
    if (comment.trim().length > BeaconPlanConsts.maxCommentLength) {
      throw const PlanTooLargeException(description: 'Comment too long');
    }
  }
}
