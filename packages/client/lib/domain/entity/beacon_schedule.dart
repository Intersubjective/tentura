import 'beacon.dart';

enum BeaconSchedulePhase {
  notStarted,
  inProgress,
  finished,
  none,
}

extension BeaconSchedule on Beacon {
  bool get hasScheduleDates => startAt != null || endAt != null;

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
