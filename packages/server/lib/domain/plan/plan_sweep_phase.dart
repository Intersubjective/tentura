/// Request plan («либретто», #220): the time phases `PlanStepSweepCase` acts
/// on (`plan-implementation.md` §4.5). Pure; the repository's candidate SQL
/// mirrors `PlanSweepPhase.key` of a step's last phase.
library;

import 'package:tentura_root/domain/plan/plan.dart';

import 'package:tentura_server/consts/beacon_plan_consts.dart';

enum PlanSweepPhaseKind {
  /// 15 minutes before an assigned step starts.
  remind,

  /// An assigned step's start has come.
  due,

  /// An assigned step is overdue (end, or start + 15 min).
  overdue,

  /// The author hears about a step 30 minutes after it became overdue.
  authorLate,

  /// A step with nobody on it started (or reached its end).
  unassignedDue,
}

final class PlanSweepPhase {
  const PlanSweepPhase({
    required this.kind,
    required this.stepId,
    required this.assigneeId,
    required this.boundary,
  });

  final PlanSweepPhaseKind kind;
  final String stepId;
  final String? assigneeId;

  /// The instant the phase is keyed on (start, overdue boundary, …).
  final DateTime boundary;

  /// Idempotency key: `plan_step:<stepId>:<phase>:<assigneeId|none>:<epochMs>`.
  /// A move or a reassignment yields a new key.
  String get key => keyOf(
    stepId: stepId,
    phase: kind,
    assigneeId: assigneeId,
    boundary: boundary,
  );

  static String keyOf({
    required String stepId,
    required PlanSweepPhaseKind phase,
    required String? assigneeId,
    required DateTime boundary,
  }) =>
      'plan_step:$stepId:${phase.name}:${assigneeId ?? 'none'}:'
      '${boundary.toUtc().millisecondsSinceEpoch}';

  /// Every phase whose time has come at [now] for one live, unticked step,
  /// in firing order. A reminder is only offered inside its window.
  static List<PlanSweepPhase> dueAt({
    required String stepId,
    required String? assigneeId,
    required DateTime? startAt,
    required DateTime? endAt,
    required DateTime now,
  }) {
    final phases = <PlanSweepPhase>[];
    PlanSweepPhase phase(PlanSweepPhaseKind kind, DateTime boundary) =>
        PlanSweepPhase(
          kind: kind,
          stepId: stepId,
          assigneeId: assigneeId,
          boundary: boundary,
        );
    if (assigneeId == null) {
      final boundary = startAt ?? endAt;
      if (boundary != null && !now.isBefore(boundary)) {
        phases.add(phase(PlanSweepPhaseKind.unassignedDue, boundary));
      }
      return phases;
    }
    final state = PlanStepState(
      id: stepId,
      title: '',
      assigneeId: assigneeId,
      startAt: startAt,
      endAt: endAt,
    );
    if (startAt != null) {
      if (now.isBefore(startAt) &&
          !now.isBefore(startAt.subtract(kPlanReminderLead))) {
        phases.add(phase(PlanSweepPhaseKind.remind, startAt));
      }
      if (!now.isBefore(startAt)) {
        phases.add(phase(PlanSweepPhaseKind.due, startAt));
      }
    }
    final overdue = state.overdueBoundary;
    if (overdue != null && !now.isBefore(overdue)) {
      phases.add(phase(PlanSweepPhaseKind.overdue, overdue));
      if (!now.isBefore(overdue.add(BeaconPlanConsts.authorLateDelay))) {
        phases.add(phase(PlanSweepPhaseKind.authorLate, overdue));
      }
    }
    return phases;
  }
}
