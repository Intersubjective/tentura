import 'package:tentura_root/domain/availability.dart';

/// Maximum inclusive calendar-day horizon for pause `resume_on` (plan §0).
const int availabilityResumeHorizonDays = 90;

/// Calendar date [date] plus [days] whole calendar days (UTC date-only).
DateTime addUtcCalendarDays(DateTime date, int days) {
  assert(isUtcCalendarDate(date));
  return DateTime.utc(date.year, date.month, date.day + days);
}

/// Tomorrow relative to [todayUtc] (`+1` calendar day).
DateTime availabilityTomorrowPreset(DateTime todayUtc) =>
    addUtcCalendarDays(todayUtc, 1);

/// Next Monday relative to [todayUtc] (`8 - weekday` days; Monday → following Monday).
DateTime availabilityThisWeekendPreset(DateTime todayUtc) {
  assert(isUtcCalendarDate(todayUtc));
  return addUtcCalendarDays(todayUtc, 8 - todayUtc.weekday);
}

/// One week relative to [todayUtc] (`+7` calendar days).
DateTime availabilityOneWeekPreset(DateTime todayUtc) =>
    addUtcCalendarDays(todayUtc, 7);

/// One calendar month later, clamping the day to the target month's final day.
DateTime availabilityOneMonthPreset(DateTime todayUtc) {
  assert(isUtcCalendarDate(todayUtc));
  var year = todayUtc.year;
  var month = todayUtc.month + 1;
  if (month > 12) {
    month = 1;
    year += 1;
  }
  final lastDay = DateTime.utc(year, month + 1, 0).day;
  final day = todayUtc.day > lastDay ? lastDay : todayUtc.day;
  return DateTime.utc(year, month, day);
}

/// Last selectable pause date: [todayUtc] + [availabilityResumeHorizonDays].
DateTime availabilityMaxResumeOn(DateTime todayUtc) =>
    addUtcCalendarDays(todayUtc, availabilityResumeHorizonDays);

/// Converts a local date-picker value to a UTC-midnight calendar date.
DateTime utcCalendarDateFromLocalPicker(DateTime picked) =>
    DateTime.utc(picked.year, picked.month, picked.day);
