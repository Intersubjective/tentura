import 'enums.dart';

/// Normalizes [value] to a UTC-midnight calendar date using its UTC year/month/day.
DateTime utcCalendarDate(DateTime value) {
  final utc = value.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}

/// True when [value] is a UTC-midnight calendar date (no time-of-day component).
bool isUtcCalendarDate(DateTime value) {
  return value.isUtc &&
      value.hour == 0 &&
      value.minute == 0 &&
      value.second == 0 &&
      value.millisecond == 0 &&
      value.microsecond == 0;
}

/// Derives the effective availability view on [todayUtc].
///
/// Paused iff [resumeOn] is set and [todayUtc] is strictly before [resumeOn].
/// On the resume date the user is available again. Limited applies when not paused.
AvailabilityView availabilityViewOn({
  required bool isLimited,
  DateTime? resumeOn,
  required DateTime todayUtc,
}) {
  assert(() {
    if (!isUtcCalendarDate(todayUtc)) {
      throw ArgumentError.value(
        todayUtc,
        'todayUtc',
        'must be a UTC calendar date',
      );
    }
    if (resumeOn != null && !isUtcCalendarDate(resumeOn)) {
      throw ArgumentError.value(
        resumeOn,
        'resumeOn',
        'must be a UTC calendar date when set',
      );
    }
    return true;
  }());

  if (resumeOn != null && todayUtc.isBefore(resumeOn)) {
    return AvailabilityView.paused;
  }
  if (isLimited) {
    return AvailabilityView.limited;
  }
  return AvailabilityView.open;
}
