import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:tentura_root/domain/plan/plan.dart';

import 'package:tentura/domain/coordination/beacon_you_plan_slots.dart';

/// One live step of a Request plan («либретто», #220) as the viewer sees it:
/// content plus the tick and the «Понятно» bookkeeping.
@immutable
final class PlanStep {
  const PlanStep({
    required this.id,
    required this.title,
    this.index = 0,
    this.description = '',
    this.assigneeId,
    this.startAt,
    this.endAt,
    this.doneAt,
    this.doneById,
    this.createdSeq = 0,
    this.contentSeq = 0,
    this.ackSeq = 0,
    this.assigneeAckPending = false,
  });

  /// Lenient: unknown keys are ignored, broken values fall back to defaults.
  factory PlanStep.fromJson(Map<String, Object?> json) => PlanStep(
    id: (json['id'] as String?) ?? '',
    index: _int(json['index']),
    title: (json['title'] as String?) ?? '',
    description: (json['description'] as String?) ?? '',
    assigneeId: _nonEmpty(json['assigneeId']),
    startAt: _instant(json['startAt']),
    endAt: _instant(json['endAt']),
    doneAt: _instant(json['doneAt']),
    doneById: _nonEmpty(json['doneById']),
    createdSeq: _int(json['createdSeq']),
    contentSeq: _int(json['contentSeq']),
    ackSeq: _int(json['ackSeq']),
    assigneeAckPending: json['assigneeAckPending'] == true,
  );

  final String id;

  /// 1-based position among live steps (one numbering everywhere).
  final int index;
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

  /// The assignee has not confirmed («Понятно») the latest change yet.
  final bool assigneeAckPending;

  bool get isDone => doneAt != null;

  bool get isUntimed => startAt == null && endAt == null;

  /// The instant the step is sorted / grouped by: its start, else its end.
  DateTime? get anchorAt => startAt ?? endAt;

  PlanStepState toState() => PlanStepState(
    id: id,
    title: title,
    assigneeId: assigneeId,
    startAt: startAt,
    endAt: endAt,
    doneAt: doneAt,
  );

  PlanStepSnapshot toSnapshot() => PlanStepSnapshot(
    id: id,
    title: title,
    description: description,
    assigneeId: assigneeId,
    startAt: startAt,
    endAt: endAt,
  );

  bool isOverdueAt(DateTime now) => toState().isOverdueAt(now);

  Duration? overdueBy(DateTime now) => toState().overdueBy(now);

  PlanStep withDone({required DateTime? doneAt, required String? doneById}) =>
      PlanStep(
        id: id,
        index: index,
        title: title,
        description: description,
        assigneeId: assigneeId,
        startAt: startAt,
        endAt: endAt,
        doneAt: doneAt,
        doneById: doneById,
        createdSeq: createdSeq,
        contentSeq: contentSeq,
        ackSeq: ackSeq,
        assigneeAckPending: assigneeAckPending,
      );

  @override
  bool operator ==(Object other) =>
      other is PlanStep &&
      other.id == id &&
      other.index == index &&
      other.title == title &&
      other.description == description &&
      other.assigneeId == assigneeId &&
      other.startAt == startAt &&
      other.endAt == endAt &&
      other.doneAt == doneAt &&
      other.doneById == doneById &&
      other.contentSeq == contentSeq &&
      other.ackSeq == ackSeq &&
      other.assigneeAckPending == assigneeAckPending;

  @override
  int get hashCode => Object.hash(
    id,
    index,
    title,
    description,
    assigneeId,
    startAt,
    endAt,
    doneAt,
    doneById,
    contentSeq,
    ackSeq,
    assigneeAckPending,
  );
}

/// One person's «Понятно» ledger row.
@immutable
final class PlanMember {
  const PlanMember({
    required this.userId,
    this.pendingFromSeq,
    this.ackedSeq = 0,
    this.ackedAt,
  });

  factory PlanMember.fromJson(Map<String, Object?> json) => PlanMember(
    userId: (json['userId'] as String?) ?? '',
    pendingFromSeq: _intOrNull(json['pendingFromSeq']),
    ackedSeq: _int(json['ackedSeq']),
    ackedAt: _instant(json['ackedAt']),
  );

  final String userId;

  /// First revision the person still has to confirm; null when nothing waits.
  final int? pendingFromSeq;
  final int ackedSeq;
  final DateTime? ackedAt;

  bool get hasPending => pendingFromSeq != null;
}

/// A change to the viewer's own steps that waits for «Понятно».
@immutable
final class PlanPendingChange {
  const PlanPendingChange({required this.seq, required this.change});

  final int seq;
  final PlanChange change;
}

/// What the viewer still has to confirm.
@immutable
final class PlanViewerPending {
  const PlanViewerPending({
    required this.fromSeq,
    required this.headSeq,
    this.changes = const [],
    this.actorIds = const [],
  });

  static PlanViewerPending? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final map = json.cast<String, Object?>();
    final rawChanges = map['changes'];
    return PlanViewerPending(
      fromSeq: _int(map['fromSeq']),
      headSeq: _int(map['headSeq']),
      changes: [
        if (rawChanges is List)
          for (final c in rawChanges)
            if (c is Map && PlanChangeOp.fromWire(c['op'] as String?) != null)
              PlanPendingChange(
                seq: _int(c['seq']),
                change: PlanChange.fromJson(c.cast<String, Object?>()),
              ),
      ],
      actorIds: _stringList(map['actorIds']),
    );
  }

  final int fromSeq;

  /// Plan head when the plan was read: «Понятно» confirms up to here.
  final int headSeq;
  final List<PlanPendingChange> changes;
  final List<String> actorIds;
}

/// The Request plan as one viewer reads it (`beaconPlan`).
///
/// Shared by the Plan tab and (part 2) the HUD / My Work rows: use
/// [viewerSchedule] and [effectiveNow] instead of re-deriving the rules.
@immutable
final class BeaconPlan {
  const BeaconPlan({
    required this.beaconId,
    this.revisionSeq = 0,
    this.changeSeq = 0,
    this.lastEditedById,
    this.lastEditedAt,
    this.copiedFromBeaconId,
    this.copiedFromTitle,
    this.editable = false,
    this.tickable = false,
    this.steps = const [],
    this.members = const [],
    this.viewerPending,
    this.names = const {},
  });

  factory BeaconPlan.fromJson(Map<String, Object?> json) {
    final rawSteps = json['steps'];
    final rawMembers = json['members'];
    final rawNames = json['names'];
    return BeaconPlan(
      beaconId: (json['beaconId'] as String?) ?? '',
      revisionSeq: _int(json['revisionSeq']),
      changeSeq: _int(json['changeSeq']),
      lastEditedById: _nonEmpty(json['lastEditedById']),
      lastEditedAt: _instant(json['lastEditedAt']),
      copiedFromBeaconId: _nonEmpty(json['copiedFromBeaconId']),
      copiedFromTitle: _nonEmpty(json['copiedFromTitle']),
      editable: json['editable'] == true,
      tickable: json['tickable'] == true,
      steps: [
        if (rawSteps is List)
          for (final s in rawSteps)
            if (s is Map) PlanStep.fromJson(s.cast<String, Object?>()),
      ].where((s) => s.id.isNotEmpty).toList(growable: false),
      members: [
        if (rawMembers is List)
          for (final m in rawMembers)
            if (m is Map) PlanMember.fromJson(m.cast<String, Object?>()),
      ],
      viewerPending: PlanViewerPending.tryFromJson(json['viewerPending']),
      names: parsePlanNames(rawNames),
    );
  }

  /// Decodes the `beaconPlan` JSON string; throws [FormatException] when
  /// it is not a JSON object.
  factory BeaconPlan.decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('beaconPlan: not an object');
    }
    return BeaconPlan.fromJson(decoded.cast<String, Object?>());
  }

  final String beaconId;

  /// Head revision; the base of the next save / restore.
  final int revisionSeq;

  /// Bumped by every plan write (ticks too): the version realtime refers to.
  final int changeSeq;
  final String? lastEditedById;
  final DateTime? lastEditedAt;
  final String? copiedFromBeaconId;
  final String? copiedFromTitle;

  /// The viewer may edit the plan (save / restore).
  final bool editable;

  /// The viewer may tick steps.
  final bool tickable;

  /// Live steps in plan order.
  final List<PlanStep> steps;
  final List<PlanMember> members;
  final PlanViewerPending? viewerPending;

  /// userId → display name for everyone the plan mentions.
  final Map<String, String> names;

  bool get isEmpty => steps.isEmpty;

  /// The plan was never written (no revisions at all).
  bool get hasHistory => revisionSeq > 0;

  int get doneCount => steps.where((s) => s.isDone).length;

  List<PlanStepState> get stepStates => [for (final s in steps) s.toState()];

  PlanSnapshot get snapshot =>
      PlanSnapshot([for (final s in steps) s.toSnapshot()]);

  PlanStep? stepById(String id) {
    for (final s in steps) {
      if (s.id == id) return s;
    }
    return null;
  }

  PlanMember? memberOf(String userId) {
    for (final m in members) {
      if (m.userId == userId) return m;
    }
    return null;
  }

  String? nameOf(String? userId) {
    if (userId == null) return null;
    final n = names[userId]?.trim();
    return n == null || n.isEmpty ? null : n;
  }

  /// The viewer's place in the plan right now (YOU / NEXT rows).
  PlanViewerSchedule viewerSchedule({
    required DateTime now,
    required String viewerId,
  }) => PlanSchedule.forViewer(viewerId, stepStates, now);

  /// All overdue live steps (Plan tab header).
  int overdueCount(DateTime now) =>
      steps.where((s) => s.isOverdueAt(now)).length;

  /// The viewer's own overdue steps (HUD counter).
  int viewerOverdueCount({required DateTime now, required String viewerId}) =>
      PlanSchedule.overdueCountFor(viewerId, stepStates, now);

  /// NOW line between the manual line and the plan (last writer wins).
  PlanNow effectiveNow({
    required String manualText,
    required DateTime? manualSetAt,
    required bool openFamily,
    required DateTime now,
  }) => PlanSchedule.effectiveNow(
    manualText: manualText,
    manualSetAt: manualSetAt,
    steps: stepStates,
    openFamily: openFamily,
    now: now,
  );

  /// The viewer has changes to confirm with «Понятно».
  bool get hasViewerPending =>
      viewerPending != null && viewerPending!.changes.isNotEmpty;

  /// Steps the viewer's pending changes touch.
  Set<String> get viewerPendingStepIds => {
    for (final c in viewerPending?.changes ?? const <PlanPendingChange>[])
      c.change.stepId,
  };

  /// Input of the HUD YOU / BY PLAN / NEXT ladder (plan §5.2).
  PlanYouInput viewerYouInput({
    required DateTime now,
    required String viewerId,
  }) => PlanYouInput(
    schedule: viewerSchedule(now: now, viewerId: viewerId),
    pendingAck: hasViewerPending,
    pendingStepIds: viewerPendingStepIds,
  );

  /// The viewer has an active (started or due) step of their own.
  bool viewerHasCurrentStep({
    required DateTime now,
    required String viewerId,
  }) => viewerSchedule(now: now, viewerId: viewerId).current != null;

  BeaconPlan withSteps(List<PlanStep> next) => BeaconPlan(
    beaconId: beaconId,
    revisionSeq: revisionSeq,
    changeSeq: changeSeq,
    lastEditedById: lastEditedById,
    lastEditedAt: lastEditedAt,
    copiedFromBeaconId: copiedFromBeaconId,
    copiedFromTitle: copiedFromTitle,
    editable: editable,
    tickable: tickable,
    steps: List.unmodifiable(next),
    members: members,
    viewerPending: viewerPending,
    names: names,
  );

  BeaconPlan withoutViewerPending() => BeaconPlan(
    beaconId: beaconId,
    revisionSeq: revisionSeq,
    changeSeq: changeSeq,
    lastEditedById: lastEditedById,
    lastEditedAt: lastEditedAt,
    copiedFromBeaconId: copiedFromBeaconId,
    copiedFromTitle: copiedFromTitle,
    editable: editable,
    tickable: tickable,
    steps: steps,
    members: members,
    names: names,
  );

  /// Optimistic tick: [stepId] marked done ([done]) by [actorId].
  BeaconPlan withStepDone(
    String stepId, {
    required bool done,
    required String actorId,
    required DateTime now,
  }) => withSteps([
    for (final s in steps)
      if (s.id == stepId)
        s.withDone(
          doneAt: done ? now.toUtc() : null,
          doneById: done ? actorId : null,
        )
      else
        s,
  ]);
}

/// Outcome of `beaconPlanSave` / `beaconPlanRestore` / «Не успеваю».
enum PlanSaveOutcomeKind { applied, merged, noop }

@immutable
final class PlanSaveOutcome {
  const PlanSaveOutcome({
    required this.kind,
    required this.revisionSeq,
    this.theirStepIds = const [],
    this.theirActorIds = const [],
  });

  factory PlanSaveOutcome.decode(String raw) {
    final decoded = jsonDecode(raw);
    final map = decoded is Map
        ? decoded.cast<String, Object?>()
        : const <String, Object?>{};
    return PlanSaveOutcome(
      kind: switch (map['outcome']) {
        'merged' => PlanSaveOutcomeKind.merged,
        'noop' => PlanSaveOutcomeKind.noop,
        _ => PlanSaveOutcomeKind.applied,
      },
      revisionSeq: _int(map['revisionSeq']),
      theirStepIds: _stringList(map['theirStepIds']),
      theirActorIds: _stringList(map['theirActorIds']),
    );
  }

  final PlanSaveOutcomeKind kind;
  final int revisionSeq;
  final List<String> theirStepIds;
  final List<String> theirActorIds;
}

/// «Не успеваю» options (server `PlanCantMakeOption`).
enum PlanCantMakeOption {
  reschedule('reschedule'),
  handover('handover'),
  chat('chat');

  const PlanCantMakeOption(this.wire);

  final String wire;
}

/// `names` maps of plan payloads.
Map<String, String> parsePlanNames(Object? raw) => raw is Map
    ? {
        for (final e in raw.entries)
          if (e.key is String && e.value is String)
            e.key as String: e.value as String,
      }
    : const {};

int _int(Object? v) => _intOrNull(v) ?? 0;

int? _intOrNull(Object? v) => switch (v) {
  final int i => i,
  final num n => n.toInt(),
  final String s => int.tryParse(s),
  _ => null,
};

String? _nonEmpty(Object? v) => v is String && v.isNotEmpty ? v : null;

DateTime? _instant(Object? v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toUtc() : null;

List<String> _stringList(Object? v) => [
  if (v is List)
    for (final e in v)
      if (e is String && e.isNotEmpty) e,
];
