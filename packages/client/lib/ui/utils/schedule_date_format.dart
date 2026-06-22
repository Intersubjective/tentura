import 'package:intl/intl.dart';

/// Absolute schedule date for the card "when" line, e.g. "8 May" — or
/// "8 May 2027" when the date is not in the current year. Locale-aware.
String formatScheduleDate(
  DateTime date, {
  required String localeName,
  required DateTime now,
}) {
  final local = date.toLocal();
  final nowLocal = now.toLocal();
  final fmt = local.year == nowLocal.year
      ? DateFormat.MMMd(localeName)
      : DateFormat.yMMMd(localeName);
  return fmt.format(local);
}

/// Absolute schedule range for an event window. Collapses to a single date when
/// start and end fall on the same calendar day; otherwise renders both sides
/// (locale-safe — no assumptions about day/month ordering), e.g.
/// "May 5 – May 8" / "5 мая – 8 мая". Year is added only when not the current
/// year.
String formatScheduleRange(
  DateTime start,
  DateTime end, {
  required String localeName,
  required DateTime now,
}) {
  final s = start.toLocal();
  final e = end.toLocal();
  if (s.year == e.year && s.month == e.month && s.day == e.day) {
    return formatScheduleDate(start, localeName: localeName, now: now);
  }
  return '${formatScheduleDate(start, localeName: localeName, now: now)}'
      ' – '
      '${formatScheduleDate(end, localeName: localeName, now: now)}';
}
