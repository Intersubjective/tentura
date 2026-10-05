import 'package:intl/intl.dart';

import 'package:tentura/ui/l10n/l10n.dart';

/// Compact remaining duration: `{days}d {hours}h` → `{hours}h {minutes}m` → `{minutes}m` → `<1m`.
String formatCompactDurationRemaining(
  Duration remaining,
  L10n l10n,
) {
  if (remaining.isNegative || remaining == Duration.zero) {
    return l10n.durationRemainingLessThanMinute;
  }
  final days = remaining.inDays;
  final hoursTotal = remaining.inHours;
  final hours = hoursTotal % 24;
  final minutes = remaining.inMinutes % 60;
  if (days > 0) {
    return l10n.durationRemainingDaysHours(days, hours);
  }
  if (hoursTotal > 0) {
    return l10n.durationRemainingHoursMinutes(hoursTotal, minutes);
  }
  if (minutes > 0) {
    return l10n.durationRemainingMinutes(minutes);
  }
  return l10n.durationRemainingLessThanMinute;
}

bool _sameCalendarDayLocal(DateTime a, DateTime b) {
  final al = a.toLocal();
  final bl = b.toLocal();
  return al.year == bl.year && al.month == bl.month && al.day == bl.day;
}

/// Concrete local time/date for closed/cancelled STATUS slot2.
///
/// Same calendar day as [now]: time only; otherwise the localized day,
/// with the year only when it is not [now]'s.
String formatBeaconLifecycleEndedAt({
  required DateTime endedAt,
  required DateTime now,
  required String localeName,
}) {
  final local = endedAt.toLocal();
  final time = DateFormat.Hm(localeName).format(local);
  if (_sameCalendarDayLocal(endedAt, now)) {
    return time;
  }
  // Earlier days drop the clock, and this year drops the year.
  final sameYear = local.year == now.toLocal().year;
  return (sameYear ? DateFormat.MMMd(localeName) : DateFormat.yMMMd(localeName))
      .format(local);
}
