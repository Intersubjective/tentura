import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/plan/plan.dart';

import 'package:tentura/domain/use_case/use_case_base.dart';

import '../../data/repository/beacon_plan_repository.dart';
import '../entity/beacon_plan.dart';
import '../entity/plan_conflict.dart';
import '../entity/plan_revision.dart';

export '../entity/beacon_plan.dart';
export '../entity/plan_conflict.dart';
export '../entity/plan_revision.dart';

/// Request plan («либретто», #220): the client-side workflow over
/// [BeaconPlanRepository] (reads, writes, conflict preparation). No UI.
@singleton
final class BeaconPlanCase extends UseCaseBase {
  BeaconPlanCase(
    this._repository, {
    required super.env,
    required super.logger,
  });

  final BeaconPlanRepository _repository;

  /// Ids of Requests whose plan changed on the server.
  Stream<String> changesFor(String beaconId) =>
      _repository.changes.where((id) => id == beaconId);

  Future<BeaconPlan> fetch(String beaconId) => _repository.fetch(beaconId);

  Future<PlanRevisionPage> revisions(String beaconId, {int? beforeSeq}) =>
      _repository.revisions(beaconId, beforeSeq: beforeSeq);

  Future<PlanRevisionSnapshot> revision(String beaconId, int seq) =>
      _repository.revision(beaconId, seq);

  Future<PlanSaveOutcome> save({
    required String beaconId,
    required int baseRevisionSeq,
    required PlanSnapshot steps,
    String comment = '',
  }) => _repository.save(
    beaconId: beaconId,
    baseRevisionSeq: baseRevisionSeq,
    steps: steps,
    comment: comment,
  );

  Future<PlanSaveOutcome> restore({
    required String beaconId,
    required int fromSeq,
    required int baseRevisionSeq,
  }) => _repository.restore(
    beaconId: beaconId,
    fromSeq: fromSeq,
    baseRevisionSeq: baseRevisionSeq,
  );

  Future<void> setDone({required String stepId, required bool done}) =>
      _repository.setDone(stepId: stepId, done: done);

  Future<void> ack({required String beaconId, required int uptoSeq}) =>
      _repository.ack(beaconId: beaconId, uptoSeq: uptoSeq);

  Future<PlanSaveOutcome> cantMake({
    required String stepId,
    required PlanCantMakeOption option,
    required int baseRevisionSeq,
    DateTime? newStartAt,
    DateTime? newEndAt,
    String? toUserId,
    String? excerpt,
  }) => _repository.cantMake(
    stepId: stepId,
    option: option,
    baseRevisionSeq: baseRevisionSeq,
    newStartAt: newStartAt,
    newEndAt: newEndAt,
    toUserId: toUserId,
    excerpt: excerpt,
  );

  /// «Не успеваю → написать в обсуждении»: records the «can't make it» on
  /// [stepId] with the sent message's own words ([excerpt]).
  Future<PlanSaveOutcome> cantMakeInChat({
    required String stepId,
    required int baseRevisionSeq,
    required String excerpt,
  }) => cantMake(
    stepId: stepId,
    option: PlanCantMakeOption.chat,
    baseRevisionSeq: baseRevisionSeq,
    excerpt: excerpt,
  );

  /// After a 1330 on save: loads the current plan and re-applies the user's
  /// edits ([mine], drafted over [base] = revision [baseSeq]) onto it. Steps
  /// both sides changed take the current version; the result names them and
  /// who changed them, so the user can check the draft before saving again.
  Future<PlanRebase> rebaseAfterConflict({
    required String beaconId,
    required int baseSeq,
    required PlanSnapshot base,
    required PlanSnapshot mine,
  }) async {
    final fresh = await _repository.fetch(beaconId);
    final theirs = fresh.snapshot;
    final conflictIds = switch (PlanMerge.threeWay(base, theirs, mine)) {
      PlanMergeMerged() => const <String>[],
      PlanMergeConflict(:final stepIds) => stepIds,
    };
    final patched = conflictIds.isEmpty
        ? mine
        : planTakeTheirSteps(mine, theirs, conflictIds);
    final draft = switch (PlanMerge.threeWay(base, theirs, patched)) {
      PlanMergeMerged(:final snapshot) => snapshot,
      // Cannot happen once their steps are taken; keep the patched draft.
      PlanMergeConflict() => patched,
    };
    if (conflictIds.isEmpty) {
      return PlanRebase(
        currentSeq: fresh.revisionSeq,
        theirs: theirs,
        draft: draft,
      );
    }
    var page = const PlanRevisionPage();
    try {
      page = await _repository.revisions(beaconId);
    } on Object catch (e) {
      logger.warning('Plan history for a conflict notice failed', e);
    }
    String? actorOf(String stepId) {
      for (final entry in page.items) {
        if (entry.seq <= baseSeq) break;
        if (entry.changes.any((c) => c.stepId == stepId)) {
          return entry.actorId;
        }
      }
      return fresh.lastEditedById;
    }

    final theirsById = theirs.byId;
    final baseById = base.byId;
    final mineById = mine.byId;
    PlanConflictStep conflictStep(String id) {
      final actorId = actorOf(id);
      final step = theirsById[id] ?? baseById[id] ?? mineById[id];
      return PlanConflictStep(
        stepId: id,
        title: step?.title ?? '',
        actorId: actorId,
        actorName: actorId == null
            ? null
            : page.names[actorId] ?? fresh.names[actorId],
      );
    }

    return PlanRebase(
      currentSeq: fresh.revisionSeq,
      theirs: theirs,
      draft: draft,
      conflicts: [for (final id in conflictIds) conflictStep(id)],
    );
  }
}
