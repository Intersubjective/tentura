/// ISO 8601 week key `<week-year>-W<week>` for [date] (UTC calendar day).
///
/// The week-year differs from the calendar year around New Year: 2027-01-01
/// still belongs to `2026-W53`. The week is the one holding that day's
/// Thursday.
String isoWeekKey(DateTime date) {
  final utc = date.toUtc();
  final day = DateTime.utc(utc.year, utc.month, utc.day);
  final thursday = day.add(Duration(days: DateTime.thursday - day.weekday));
  final week =
      thursday.difference(DateTime.utc(thursday.year)).inDays ~/ 7 + 1;
  return '${thursday.year}-W${week.toString().padLeft(2, '0')}';
}
