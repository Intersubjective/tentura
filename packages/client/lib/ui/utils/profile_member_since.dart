import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/schedule_date_format.dart';

enum ProfileTenureUnit { days, months, years }

/// Whole calendar days from [joinedAt] to [now] (local calendar days).
int profileTenureCalendarDays({
  required DateTime joinedAt,
  required DateTime now,
}) {
  final joinLocal = joinedAt.toLocal();
  final nowLocal = now.toLocal();
  final joinDay = DateTime(joinLocal.year, joinLocal.month, joinLocal.day);
  final today = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
  final days = today.difference(joinDay).inDays;
  return days < 0 ? 0 : days;
}

/// Full calendar months between join date and [now] (day-of-month aware).
int profileTenureCalendarMonths({
  required DateTime joinedAt,
  required DateTime now,
}) {
  final joinLocal = joinedAt.toLocal();
  final nowLocal = now.toLocal();
  var months =
      (nowLocal.year - joinLocal.year) * 12 +
      (nowLocal.month - joinLocal.month);
  if (nowLocal.day < joinLocal.day) {
    months--;
  }
  return months < 0 ? 0 : months;
}

({int count, ProfileTenureUnit unit}) profileTenureSegment({
  required DateTime joinedAt,
  required DateTime now,
}) {
  final months = profileTenureCalendarMonths(joinedAt: joinedAt, now: now);
  if (months >= 12) {
    return (count: months ~/ 12, unit: ProfileTenureUnit.years);
  }
  if (months >= 1) {
    return (count: months, unit: ProfileTenureUnit.months);
  }
  return (
    count: profileTenureCalendarDays(joinedAt: joinedAt, now: now),
    unit: ProfileTenureUnit.days,
  );
}

String profileTenureDurationLabel({
  required L10n l10n,
  required DateTime joinedAt,
  required DateTime now,
}) {
  final segment = profileTenureSegment(joinedAt: joinedAt, now: now);
  return switch (segment.unit) {
    ProfileTenureUnit.days => l10n.profileTenureDays(segment.count),
    ProfileTenureUnit.months => l10n.profileTenureMonths(segment.count),
    ProfileTenureUnit.years => l10n.profileTenureYears(segment.count),
  };
}

String profileMemberSinceDisplayLine({
  required L10n l10n,
  required DateTime joinedAt,
  required DateTime now,
}) {
  final date = formatScheduleDate(
    joinedAt,
    localeName: l10n.localeName,
    now: now,
  );
  final segment = profileTenureSegment(joinedAt: joinedAt, now: now);
  if (segment.unit == ProfileTenureUnit.days && segment.count == 0) {
    return l10n.profileMemberSinceJoinedToday(date);
  }
  final tenure = profileTenureDurationLabel(
    l10n: l10n,
    joinedAt: joinedAt,
    now: now,
  );
  return l10n.profileMemberSince(date, tenure);
}
