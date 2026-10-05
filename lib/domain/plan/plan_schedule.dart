/// Request plan («либретто», #220): who does what now, by the clock.
///
/// Pure functions shared by the server (sweep, obligations, My Work slice) and
/// the client (HUD, Plan tab), so both sides agree on «your step», «next»,
/// «overdue» and the NOW line.
library;

/// How long after its start a step with no end becomes overdue (owner Q1).
const kPlanUntimedOverdueGrace = Duration(minutes: 15);

/// Reminder lead before a step starts (decision 7).
const kPlanReminderLead = Duration(minutes: 15);

/// The live state of one plan step (content plus tick), in plan order.
final class PlanStepState {
  const PlanStepState({
    required this.id,
    required this.title,
    this.assigneeId,
    this.startAt,
    this.endAt,
    this.doneAt,
  });

  final String id;
  final String title;
  final String? assigneeId;
  final DateTime? startAt;
  final DateTime? endAt;
  final DateTime? doneAt;

  bool get isDone => doneAt != null;

  /// When the step becomes overdue: its end; with no end, start + 15 min;
  /// a step with no time is never overdue.
  DateTime? get overdueBoundary =>
      endAt ?? startAt?.add(kPlanUntimedOverdueGrace);

  bool isOverdueAt(DateTime now) {
    if (isDone) return false;
    final boundary = overdueBoundary;
    return boundary != null && !now.isBefore(boundary);
  }

  /// How late the step is, or null when it is not overdue.
  Duration? overdueBy(DateTime now) =>
      isOverdueAt(now) ? now.difference(overdueBoundary!) : null;
}

/// One viewer's place in the plan right now.
final class PlanViewerSchedule {
  const PlanViewerSchedule({
    this.current,
    this.alsoActive = const [],
    this.next,
    this.freeUntil,
  });

  /// The step expected from the viewer now (YOU row).
  final PlanStepState? current;

  /// Other active steps of the viewer («тоже идёт»).
  final List<PlanStepState> alsoActive;

  /// The viewer's next step after the active ones («ДАЛЬШЕ»).
  final PlanStepState? next;

  /// Start of the viewer's nearest future step when nothing is active.
  final DateTime? freeUntil;

  bool get hasAny => current != null || next != null;
}

abstract final class PlanSchedule {
  /// Whether step [index] of [steps] (live steps, plan order) is active.
  ///
  /// A step with a start is active once the start has come. A step without a
  /// start (no time, or only an end) is active when it is the first step or
  /// the previous step of the plan is done (owner Q2).
  static bool isActive(List<PlanStepState> steps, int index, DateTime now) {
    final step = steps[index];
    final start = step.startAt;
    if (start != null) return !now.isBefore(start);
    if (index == 0) return true;
    return steps[index - 1].isDone;
  }

  /// [steps] are the live (not removed) steps in plan order.
  static PlanViewerSchedule forViewer(
    String viewerId,
    List<PlanStepState> steps,
    DateTime now,
  ) {
    final active = <PlanStepState>[];
    final waiting = <PlanStepState>[];
    for (var i = 0; i < steps.length; i++) {
      final s = steps[i];
      if (s.assigneeId != viewerId || s.isDone) continue;
      (isActive(steps, i, now) ? active : waiting).add(s);
    }
    // Overdue steps go before steps that merely started (plan P19).
    final ordered = [
      ...active.where((s) => s.isOverdueAt(now)),
      ...active.where((s) => !s.isOverdueAt(now)),
    ];
    final current = ordered.isEmpty ? null : ordered.first;
    final next = waiting.isEmpty ? null : waiting.first;
    DateTime? freeUntil;
    if (current == null) {
      for (final s in waiting) {
        final start = s.startAt;
        if (start == null || !start.isAfter(now)) continue;
        if (freeUntil == null || start.isBefore(freeUntil)) freeUntil = start;
      }
    }
    return PlanViewerSchedule(
      current: current,
      alsoActive: ordered.length > 1 ? ordered.sublist(1) : const [],
      next: next,
      freeUntil: freeUntil,
    );
  }

  /// Steps of [viewerId] that are overdue now.
  static int overdueCountFor(
    String viewerId,
    List<PlanStepState> steps,
    DateTime now,
  ) =>
      steps.where((s) => s.assigneeId == viewerId && s.isOverdueAt(now)).length;

  /// How many live steps are ticked.
  static int doneCount(List<PlanStepState> steps) =>
      steps.where((s) => s.isDone).length;

  /// NOW line: the manual line or the plan step that started last, whichever
  /// is newer (last writer wins; a step starting counts as a write).
  ///
  /// [manualSetAt] is when the manual line was last written. Outside the open
  /// family (review, closed, …) the manual line always wins.
  static PlanNow effectiveNow({
    required String manualText,
    required DateTime? manualSetAt,
    required List<PlanStepState> steps,
    required bool openFamily,
    required DateTime now,
  }) {
    final manual = manualText.trim().isEmpty
        ? const PlanNow.none()
        : PlanNow.manual(setAt: manualSetAt);
    if (!openFamily || steps.isEmpty) return manual;
    PlanStepState? arrival;
    var arrivalIndex = -1;
    for (var i = 0; i < steps.length; i++) {
      final s = steps[i];
      final start = s.startAt;
      if (start == null || start.isAfter(now)) continue;
      // A step ticked before it even started never takes the NOW line.
      final done = s.doneAt;
      if (done != null && done.isBefore(start)) continue;
      if (arrival == null || start.isAfter(arrival.startAt!)) {
        arrival = s;
        arrivalIndex = i;
      } else if (start.isAtSameMomentAs(arrival.startAt!)) {
        // Same start: the first not-done step in plan order, else the last.
        if (arrival.isDone) {
          arrival = s;
          arrivalIndex = i;
        }
      }
    }
    if (arrival == null) return manual;
    final setAt = manualSetAt;
    final planWins =
        manual.source == PlanNowSource.none ||
        setAt == null ||
        arrival.startAt!.isAfter(setAt);
    if (!planWins) return manual;
    return PlanNow.plan(
      step: arrival,
      index: arrivalIndex + 1,
      count: steps.length,
    );
  }
}

enum PlanNowSource { none, manual, plan }

/// Which line the NOW row shows.
final class PlanNow {
  const PlanNow.none()
    : source = PlanNowSource.none,
      step = null,
      index = 0,
      count = 0,
      setAt = null;

  const PlanNow.manual({this.setAt})
    : source = PlanNowSource.manual,
      step = null,
      index = 0,
      count = 0;

  PlanNow.plan({
    required PlanStepState this.step,
    required this.index,
    required this.count,
  }) : source = PlanNowSource.plan,
       setAt = step.startAt;

  final PlanNowSource source;

  /// The plan step on the NOW row (when [source] is [PlanNowSource.plan]).
  final PlanStepState? step;

  /// 1-based position among live steps; one numbering everywhere.
  final int index;
  final int count;
  final DateTime? setAt;

  bool get isPlan => source == PlanNowSource.plan;
}
