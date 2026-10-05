import 'package:tentura_root/domain/plan/plan_schedule.dart';

/// What the Request plan («либретто», #220) says about the viewer, for the
/// YOU / BY PLAN / NEXT ladder of the HUD (plan §5.2).
final class PlanYouInput {
  const PlanYouInput({
    this.schedule = const PlanViewerSchedule(),
    this.pendingAck = false,
    this.pendingStepIds = const {},
  });

  /// `PlanSchedule.forViewer` for the viewer at the HUD's «now».
  final PlanViewerSchedule schedule;

  /// The viewer has plan changes to confirm («Понятно»).
  final bool pendingAck;

  /// Steps the pending changes touch.
  final Set<String> pendingStepIds;

  bool get isEmpty =>
      !pendingAck && !schedule.hasAny && schedule.freeUntil == null;
}

enum PlanYouSlotKind {
  /// Changes to the viewer's steps that wait for «Понятно».
  pendingAck,

  /// A plan step (current, also running, or upcoming).
  step,

  /// «Вы свободны до …»: nothing active, the nearest step starts later.
  freeUntil,
}

/// One plan row of the ladder.
final class PlanYouSlot {
  const PlanYouSlot.pendingAck({this.step, this.canTick = false})
    : kind = PlanYouSlotKind.pendingAck,
      alsoRunning = false,
      overdueBy = null,
      freeUntil = null,
      actionable = true;

  const PlanYouSlot.step(
    PlanStepState this.step, {
    this.alsoRunning = false,
    this.overdueBy,
    this.actionable = false,
  }) : kind = PlanYouSlotKind.step,
       freeUntil = null,
       canTick = actionable;

  const PlanYouSlot.freeUntil(DateTime this.freeUntil)
    : kind = PlanYouSlotKind.freeUntil,
      step = null,
      alsoRunning = false,
      overdueBy = null,
      actionable = false,
      canTick = false;

  final PlanYouSlotKind kind;

  /// The step of a [PlanYouSlotKind.step] row; for a pending row, the
  /// viewer's current step when the change touches it.
  final PlanStepState? step;

  /// Another active step of the viewer («тоже идёт»), shown under NEXT.
  final bool alsoRunning;

  /// How late the step is; null when it is not overdue.
  final Duration? overdueBy;

  final DateTime? freeUntil;

  /// The row carries actions ([Готово] [Не успеваю] / [Понятно]); NEXT rows
  /// never do (like the next piece in Tetris).
  final bool actionable;

  /// The row offers a one-tap «Готово» for [step].
  final bool canTick;
}

/// The plan rows of the HUD ladder. A null slot means «no plan row here»: for
/// [you] the existing YOU row (system situation or fallback) stays.
final class BeaconYouPlanSlots {
  const BeaconYouPlanSlots({this.you, this.byPlan, this.next});

  static const empty = BeaconYouPlanSlots();

  /// Replaces the YOU row's content.
  final PlanYouSlot? you;

  /// «ПО ПЛАНУ»: the plan's ask when a system situation holds YOU, or the
  /// current step when a pending change holds it.
  final PlanYouSlot? byPlan;

  /// «ДАЛЬШЕ»: what comes after, muted, no actions.
  final PlanYouSlot? next;

  bool get isEmpty => you == null && byPlan == null && next == null;
}

/// The YOU / BY PLAN / NEXT ladder (plan §5.2).
///
/// 0. The Request is finished → no plan rows.
/// 1. A system situation holds YOU ([systemOccupiesYou]: offers to review, a
///    helper's standing message, …) → BY PLAN shows the pending change, else
///    the current step; NEXT shows the current step when the pending change
///    took BY PLAN, else what comes next.
/// 2. A pending change → YOU; BY PLAN = the current step if the change does
///    not touch it; NEXT = an «also running» step or the next one.
/// 3. A current step → YOU (overdue first, plan P19); NEXT as above.
/// 4. Only future steps → YOU «free until …» when the next one has a start;
///    NEXT = the next step.
/// 5. Nothing for the viewer → no plan rows.
///
/// The group never exceeds three rows, and a pending change never drops.
BeaconYouPlanSlots deriveBeaconYouPlanSlots({
  required PlanYouInput plan,
  required bool systemOccupiesYou,
  required bool requestFinished,
  required DateTime now,
}) {
  if (requestFinished || plan.isEmpty) return BeaconYouPlanSlots.empty;
  final schedule = plan.schedule;
  final current = schedule.current;
  final pendingTouchesCurrent =
      current != null && plan.pendingStepIds.contains(current.id);

  final pending = plan.pendingAck
      ? PlanYouSlot.pendingAck(
          step: pendingTouchesCurrent ? current : null,
          canTick: pendingTouchesCurrent,
        )
      : null;
  final currentSlot = current == null
      ? null
      : PlanYouSlot.step(
          current,
          overdueBy: current.overdueBy(now),
          actionable: true,
        );
  final following = schedule.alsoActive.isNotEmpty
      ? PlanYouSlot.step(schedule.alsoActive.first, alsoRunning: true)
      : schedule.next == null
      ? null
      : PlanYouSlot.step(schedule.next!);

  if (systemOccupiesYou) {
    if (pending != null) {
      return BeaconYouPlanSlots(
        byPlan: pending,
        next: current == null || pendingTouchesCurrent
            ? following
            : PlanYouSlot.step(current, overdueBy: current.overdueBy(now)),
      );
    }
    return BeaconYouPlanSlots(byPlan: currentSlot, next: following);
  }

  if (pending != null) {
    return BeaconYouPlanSlots(
      you: pending,
      byPlan: pendingTouchesCurrent ? null : currentSlot,
      next: following,
    );
  }

  if (currentSlot != null) {
    return BeaconYouPlanSlots(you: currentSlot, next: following);
  }

  final freeUntil = schedule.freeUntil;
  return BeaconYouPlanSlots(
    you: freeUntil == null ? null : PlanYouSlot.freeUntil(freeUntil),
    next: following,
  );
}
