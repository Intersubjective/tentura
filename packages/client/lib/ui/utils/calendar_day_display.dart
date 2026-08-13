import 'package:intl/intl.dart';

import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/availability.dart';

/// Whole calendar days from [from] to [to] (both date-only; [to] may equal [from]).
int calendarDaysBetween(DateTime from, DateTime to) {
  final fromUtc = DateTime.utc(from.year, from.month, from.day);
  final toUtc = DateTime.utc(to.year, to.month, to.day);
  return toUtc.difference(fromUtc).inDays;
}

/// Midnight on the same y/m/d for [DateFormat] without calling [DateTime.toLocal].
DateTime _displayCalendarMidnight(DateTime dateOnly) =>
    DateTime(dateOnly.year, dateOnly.month, dateOnly.day);

/// Localized weekday (`EEE`) for a date-only value.
String formatCalendarWeekdayLabel(L10n l10n, DateTime dateOnly) {
  return DateFormat('EEE', l10n.localeName).format(
    _displayCalendarMidnight(dateOnly),
  );
}

/// Localized long date (`yMMMd`) for a date-only value.
String formatCalendarLongDateLabel(L10n l10n, DateTime dateOnly) {
  return DateFormat.yMMMd(l10n.localeName).format(
    _displayCalendarMidnight(dateOnly),
  );
}

/// Future [date] relative to [today]: weekday when fewer than 7 calendar days
/// away; localized date at 7+ days. Both operands are date-only (never instants).
///
/// [date] must be strictly after [today].
String formatFutureCalendarDayLabel(
  L10n l10n,
  DateTime date,
  DateTime today,
) {
  assert(isUtcCalendarDate(date) || _isLocalCalendarMidnight(date));
  assert(isUtcCalendarDate(today) || _isLocalCalendarMidnight(today));
  final days = calendarDaysBetween(today, date);
  assert(days > 0, 'formatFutureCalendarDayLabel requires a future date');
  if (days < 7) {
    return formatCalendarWeekdayLabel(l10n, date);
  }
  return formatCalendarLongDateLabel(l10n, date);
}

bool _isLocalCalendarMidnight(DateTime value) =>
    !value.isUtc &&
    value.hour == 0 &&
    value.minute == 0 &&
    value.second == 0 &&
    value.millisecond == 0 &&
    value.microsecond == 0;
