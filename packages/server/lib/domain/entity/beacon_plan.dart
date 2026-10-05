/// Request plan («либретто», #220) storage records (m0223).
library;

import 'package:tentura_root/domain/plan/plan.dart';

/// `beacon_plan`: one head row per Request.
final class BeaconPlanHead {
  const BeaconPlanHead({
    required this.beaconId,
    required this.revisionSeq,
    required this.changeSeq,
    this.lastEditedById,
    this.lastEditedAt,
    this.copiedFromBeaconId,
    this.copiedFromSeq,
  });

  final String beaconId;
  final int revisionSeq;
  final int changeSeq;
  final String? lastEditedById;
  final DateTime? lastEditedAt;
  final String? copiedFromBeaconId;
  final int? copiedFromSeq;
}

/// A plan step row (`coordination_item` kind 6).
final class PlanStepRecord {
  const PlanStepRecord({
    required this.id,
    required this.beaconId,
    required this.ordering,
    required this.title,
    required this.description,
    required this.createdSeq,
    required this.contentSeq,
    required this.ackSeq,
    this.assigneeId,
    this.startAt,
    this.endAt,
    this.doneAt,
    this.doneById,
    this.removedSeq,
    this.sourceItemId,
  });

  final String id;
  final String beaconId;
  final int ordering;
  final String title;
  final String description;
  final String? assigneeId;
  final DateTime? startAt;
  final DateTime? endAt;
  final DateTime? doneAt;
  final String? doneById;
  final int createdSeq;
  final int contentSeq;
  final int ackSeq;
  final int? removedSeq;
  final String? sourceItemId;

  bool get isRemoved => removedSeq != null;

  bool get isDone => doneAt != null;

  PlanStepSnapshot get snapshot => PlanStepSnapshot(
    id: id,
    title: title,
    description: description,
    assigneeId: assigneeId,
    startAt: startAt,
    endAt: endAt,
  );

  PlanStepState get state => PlanStepState(
    id: id,
    title: title,
    assigneeId: assigneeId,
    startAt: startAt,
    endAt: endAt,
    doneAt: doneAt,
  );
}

/// `beacon_plan_revision`.
final class PlanRevisionRecord {
  const PlanRevisionRecord({
    required this.beaconId,
    required this.seq,
    required this.kind,
    required this.snapshot,
    required this.changes,
    required this.comment,
    required this.createdAt,
    this.baseSeq,
    this.actorId,
    this.restoredFromSeq,
  });

  final String beaconId;
  final int seq;
  final int? baseSeq;
  final int kind;
  final String? actorId;
  final int? restoredFromSeq;
  final String comment;
  final PlanSnapshot snapshot;

  /// Raw `changes_json` entries (l10n-neutral, see `PlanChange.toJson`).
  final List<Map<String, Object?>> changes;
  final DateTime createdAt;

  /// People whose own steps this revision touched (need «Понятно»).
  Set<String> get affectedUserIds => PlanDiff.affectedUserIds([
    for (final c in changes)
      if (PlanChangeOp.fromWire(c['op'] as String?) != null)
        PlanChange.fromJson(c),
  ]);
}

/// `beacon_plan_member`: the «Понятно» ledger of one person.
final class PlanMemberRecord {
  const PlanMemberRecord({
    required this.beaconId,
    required this.userId,
    required this.ackedSeq,
    this.pendingFromSeq,
    this.ackedAt,
  });

  final String beaconId;
  final String userId;
  final int? pendingFromSeq;
  final int ackedSeq;
  final DateTime? ackedAt;

  bool get isPending => pendingFromSeq != null;
}

/// The Request facts a plan write is gated on, read under the lock.
final class PlanRequestInfo {
  const PlanRequestInfo({
    required this.beaconId,
    required this.kind,
    required this.status,
    required this.authorId,
    required this.title,
  });

  final String beaconId;
  final int kind;
  final int status;
  final String authorId;
  final String title;
}

enum PlanSaveOutcomeKind { applied, merged, noop }

/// Result of a save / restore / «Не успеваю».
final class PlanSaveOutcome {
  const PlanSaveOutcome({
    required this.kind,
    required this.revisionSeq,
    this.theirStepIds = const {},
    this.theirActorIds = const {},
  });

  final PlanSaveOutcomeKind kind;
  final int revisionSeq;
  final Set<String> theirStepIds;
  final Set<String> theirActorIds;

  Map<String, Object?> toJson() => {
    'outcome': kind.name,
    'revisionSeq': revisionSeq,
    'theirStepIds': theirStepIds.toList(),
    'theirActorIds': theirActorIds.toList(),
  };
}

/// One plan revision as the My Work slice reads it (pending «Понятно»).
final class PlanPendingRevision {
  const PlanPendingRevision({
    required this.seq,
    required this.changes,
    required this.createdAt,
    this.actorId,
    this.actorName,
  });

  final int seq;
  final String? actorId;

  /// The actor's display name (read along, so the slice needs no second
  /// query).
  final String? actorName;

  /// Raw `changes_json` entries.
  final List<Map<String, Object?>> changes;
  final DateTime createdAt;
}

/// Everything the My Work / inbox plan slice (`planSliceJson`, plan §4.9)
/// needs about one Request for one viewer, read in one batched statement.
final class PlanSliceSource {
  const PlanSliceSource({
    required this.beaconId,
    required this.status,
    required this.revisionSeq,
    required this.steps,
    this.pendingFromSeq,
    this.pendingRevisions = const [],
  });

  final String beaconId;

  /// `beacon.status` smallint.
  final int status;

  /// Plan head (`0` when the plan was never written).
  final int revisionSeq;

  /// Live steps in plan order.
  final List<PlanStepRecord> steps;

  /// The viewer's `beacon_plan_member.pending_from_seq`.
  final int? pendingFromSeq;

  /// Revisions from [pendingFromSeq] on, oldest first (empty when nothing
  /// is pending).
  final List<PlanPendingRevision> pendingRevisions;
}
