import 'package:meta/meta.dart';

import 'beacon_plan.dart';

/// The new time of one source step when a Request is copied with its plan
/// (plan §4.10, §5.11). Wire: `PlanStepTimeInput`.
@immutable
final class PlanStepTime {
  const PlanStepTime({
    required this.sourceStepId,
    this.startAt,
    this.endAt,
  });

  final String sourceStepId;
  final DateTime? startAt;
  final DateTime? endAt;

  @override
  bool operator ==(Object other) =>
      other is PlanStepTime &&
      other.sourceStepId == sourceStepId &&
      other.startAt == startAt &&
      other.endAt == endAt;

  @override
  int get hashCode => Object.hash(sourceStepId, startAt, endAt);

  @override
  String toString() => 'PlanStepTime($sourceStepId, $startAt, $endAt)';
}

/// How far the whole plan moves: whole calendar days plus minutes of the
/// day, both measured in the viewer's zone.
typedef PlanCopyShift = ({int days, int minutes});

/// The instant the copy is anchored on: the start (else the end) of the
/// first step, in plan order, that has a time. Null when no step is timed.
DateTime? planCopySourceAnchor(List<PlanStep> steps) {
  for (final step in steps) {
    final at = step.anchorAt;
    if (at != null) return at;
  }
  return null;
}

/// The shift that moves [sourceAnchor] onto [newAnchor]: the difference of
/// their local calendar dates, and of their local times of day.
PlanCopyShift planCopyShift({
  required DateTime sourceAnchor,
  required DateTime newAnchor,
}) {
  final s = sourceAnchor.toLocal();
  final n = newAnchor.toLocal();
  // Date-only difference through UTC midnights, so a DST day still counts 1.
  final days = DateTime.utc(
    n.year,
    n.month,
    n.day,
  ).difference(DateTime.utc(s.year, s.month, s.day)).inDays;
  final minutes = (n.hour * 60 + n.minute) - (s.hour * 60 + s.minute);
  return (days: days, minutes: minutes);
}

/// [instant] moved by [shift] with calendar arithmetic in the local zone:
/// 08:30 stays 08:30 across a DST change, and durations between steps keep
/// their wall-clock length.
DateTime shiftPlanInstant(DateTime instant, PlanCopyShift shift) {
  final l = instant.toLocal();
  return DateTime(
    l.year,
    l.month,
    l.day + shift.days,
    l.hour,
    l.minute + shift.minutes,
    l.second,
  ).toUtc();
}

/// Every live step's time in the copy, in plan order: timed steps moved by
/// [shift], untimed steps kept untimed. Assignees are never part of it.
List<PlanStepTime> planCopyStepTimes(
  List<PlanStep> steps,
  PlanCopyShift shift,
) => [
  for (final step in steps)
    PlanStepTime(
      sourceStepId: step.id,
      startAt: step.startAt == null
          ? null
          : shiftPlanInstant(step.startAt!, shift),
      endAt: step.endAt == null ? null : shiftPlanInstant(step.endAt!, shift),
    ),
];

/// Where the copy's anchor starts: the source anchor while it is still
/// ahead, else the same local time of day on the first day it is ahead.
DateTime defaultPlanCopyAnchor({
  required DateTime sourceAnchor,
  required DateTime now,
}) {
  if (sourceAnchor.isAfter(now)) return sourceAnchor;
  final s = sourceAnchor.toLocal();
  final n = now.toLocal();
  var candidate = DateTime(n.year, n.month, n.day, s.hour, s.minute);
  if (!candidate.isAfter(n)) {
    candidate = DateTime(n.year, n.month, n.day + 1, s.hour, s.minute);
  }
  return candidate.toUtc();
}
