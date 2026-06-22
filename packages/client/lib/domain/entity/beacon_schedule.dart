import 'beacon.dart';

enum BeaconSchedulePhase {
  notStarted,
  inProgress,
  finished,
  none,
}

/// Declared meaning of a beacon's schedule dates, derived purely from which
/// field is set (no stored field). The create form writes the matching
/// nullability, so this is the single source of truth for vocabulary/tone.
///
/// - [event]: `startAt` set (single moment if no `endAt`; window if both).
/// - [deadline]: only `endAt` set — "needs to happen by".
/// - [none]: no dates.
enum BeaconScheduleKind {
  none,
  deadline,
  event,
}

extension BeaconSchedule on Beacon {
  bool get hasScheduleDates => startAt != null || endAt != null;

  BeaconScheduleKind get scheduleKind {
    if (startAt != null) return BeaconScheduleKind.event;
    if (endAt != null) return BeaconScheduleKind.deadline;
    return BeaconScheduleKind.none;
  }

  BeaconSchedulePhase schedulePhase({DateTime? now}) {
    if (!hasScheduleDates) {
      return BeaconSchedulePhase.none;
    }
    final clock = now ?? DateTime.now();
    final start = startAt;
    if (start != null && clock.isBefore(start)) {
      return BeaconSchedulePhase.notStarted;
    }
    final end = endAt;
    if (end != null && !clock.isBefore(end)) {
      return BeaconSchedulePhase.finished;
    }
    return BeaconSchedulePhase.inProgress;
  }

  /// Instant the UI counts toward (startAt / endAt) or from (endAt when finished).
  DateTime? scheduleReferenceAt({DateTime? now}) {
    return switch (schedulePhase(now: now)) {
      BeaconSchedulePhase.notStarted => startAt,
      BeaconSchedulePhase.inProgress => endAt,
      BeaconSchedulePhase.finished => endAt,
      BeaconSchedulePhase.none => null,
    };
  }
}
