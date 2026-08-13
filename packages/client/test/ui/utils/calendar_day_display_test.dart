import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/calendar_day_display.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ru');
  });

  final l10n = lookupL10n(const Locale('en'));
  final today = DateTime.utc(2026, 6, 1); // Monday

  group('formatFutureCalendarDayLabel', () {
    test('uses weekday for six calendar days ahead', () {
      final date = DateTime.utc(2026, 6, 7); // Sunday, 6 days
      final label = formatFutureCalendarDayLabel(l10n, date, today);
      expect(label, DateFormat('EEE', 'en').format(DateTime(2026, 6, 7)));
      expect(label, isNot(contains('2026')));
    });

    test('uses localized date at seven calendar days', () {
      final date = DateTime.utc(2026, 6, 8); // Monday, 7 days
      final label = formatFutureCalendarDayLabel(l10n, date, today);
      expect(
        label,
        DateFormat.yMMMd('en').format(DateTime(2026, 6, 8)),
      );
    });

    test('uses localized date beyond seven days', () {
      final date = DateTime.utc(2026, 6, 30);
      expect(
        formatFutureCalendarDayLabel(l10n, date, today),
        DateFormat.yMMMd('en').format(DateTime(2026, 6, 30)),
      );
    });

    test('month-end dates keep calendar day under non-UTC process TZ', () {
      final jan31 = DateTime.utc(2026, 1, 31);
      final feb28 = DateTime.utc(2026, 2, 28);
      expect(
        formatFutureCalendarDayLabel(l10n, feb28, jan31),
        DateFormat.yMMMd('en').format(DateTime(2026, 2, 28)),
      );
    });

    test('leap-year Feb 29 formats without day shift', () {
      final feb28 = DateTime.utc(2024, 2, 28);
      final feb29 = DateTime.utc(2024, 2, 29);
      expect(
        formatFutureCalendarDayLabel(l10n, feb29, feb28),
        DateFormat('EEE', 'en').format(DateTime(2024, 2, 29)),
      );
    });

    test('ninety-day horizon uses long date', () {
      final horizon = DateTime.utc(2026, 8, 30);
      expect(
        formatFutureCalendarDayLabel(l10n, horizon, today),
        DateFormat.yMMMd('en').format(DateTime(2026, 8, 30)),
      );
    });
  });

  group('non-UTC timezone day-shift guard', () {
    test('UTC midnight availability date keeps y/m/d when formatted', () {
      final utcDate = DateTime.utc(2026, 3, 15);
      final label = formatCalendarLongDateLabel(l10n, utcDate);
      expect(label, contains('15'));
      expect(label, contains('Mar'));
      expect(label, isNot(contains('14')));
    });

    test('weekday label uses calendar components not instant local shift', () {
      final utcDate = DateTime.utc(2026, 3, 15); // Sunday UTC
      final label = formatCalendarWeekdayLabel(l10n, utcDate);
      expect(label, DateFormat('EEE', 'en').format(DateTime(2026, 3, 15)));
    });
  });

  group('calendarDaysBetween', () {
    test('counts whole calendar days across month boundaries', () {
      expect(
        calendarDaysBetween(
          DateTime.utc(2026, 1, 31),
          DateTime.utc(2026, 2, 1),
        ),
        1,
      );
    });
  });
}
