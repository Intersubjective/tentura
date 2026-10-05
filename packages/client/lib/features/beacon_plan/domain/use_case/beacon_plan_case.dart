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

  /// After a 1330 on save: loads the draft's base and the current head and
  /// re-runs the three-way merge locally. Returns a [PlanConflict] when steps
  /// really conflict, or the merged snapshot to save on top of [currentSeq].
  Future<PlanConflictCheck> prepareResave({
    required String beaconId,
    required int baseSeq,
    required int currentSeq,
    required PlanSnapshot mine,
  }) async {
    final base = baseSeq <= 0
        ? PlanSnapshot.empty
        : (await _repository.revision(beaconId, baseSeq)).snapshot;
    final theirs = currentSeq <= 0
        ? PlanSnapshot.empty
        : (await _repository.revision(beaconId, currentSeq)).snapshot;
    return switch (PlanMerge.threeWay(base, theirs, mine)) {
      PlanMergeMerged(:final snapshot) => PlanConflictCheck.merged(
        snapshot: snapshot,
        currentSeq: currentSeq,
      ),
      PlanMergeConflict(:final stepIds) => PlanConflictCheck.conflict(
        PlanConflict(
          base: base,
          theirs: theirs,
          mine: mine,
          currentSeq: currentSeq,
          stepIds: stepIds,
        ),
      ),
    };
  }
}

/// Result of [BeaconPlanCase.prepareResave].
final class PlanConflictCheck {
  const PlanConflictCheck.merged({
    required PlanSnapshot this.snapshot,
    required this.currentSeq,
  }) : conflict = null;

  PlanConflictCheck.conflict(PlanConflict this.conflict)
    : snapshot = null,
      currentSeq = conflict.currentSeq;

  final PlanSnapshot? snapshot;
  final PlanConflict? conflict;
  final int currentSeq;
}
