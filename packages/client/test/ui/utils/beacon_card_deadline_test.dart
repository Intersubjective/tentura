import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/beacon_card_deadline.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
  });

  final l10n = lookupL10n(const Locale('en'));
  final now = DateTime(2026, 6, 22, 12);

  group('beaconCardCalendarDeadlineStatus', () {
    test('returns null when endAt is null', () {
      expect(beaconCardCalendarDeadlineStatus(l10n, null, now: now), isNull);
    });

    test('marks past deadline as overdue', () {
      final status = beaconCardCalendarDeadlineStatus(
        l10n,
        now.subtract(const Duration(hours: 1)),
        now: now,
      );
      expect(status?.text, l10n.myWorkStatusOverdue);
      expect(status?.overdue, isTrue);
    });

    test('marks same calendar day as due today', () {
      final status = beaconCardCalendarDeadlineStatus(
        l10n,
        DateTime(2026, 6, 22, 23, 59),
        now: now,
      );
      expect(status?.text, l10n.myWorkStatusDueToday);
      expect(status?.overdue, isFalse);
    });

    test('marks next calendar day as due tomorrow', () {
      final status = beaconCardCalendarDeadlineStatus(
        l10n,
        DateTime(2026, 6, 23, 8),
        now: now,
      );
      expect(status?.text, l10n.myWorkStatusDueTomorrow);
      expect(status?.overdue, isFalse);
    });

    test('uses weekday label for later dates', () {
      final endAt = DateTime(2026, 6, 27, 18);
      final status = beaconCardCalendarDeadlineStatus(l10n, endAt, now: now);
      expect(status?.text, l10n.myWorkStatusDueWeekday('Sat'));
      expect(status?.overdue, isFalse);
    });
  });

  group('beaconCardDeadlineRemainingMeta', () {
    test('returns null when endAt is null', () {
      expect(beaconCardDeadlineRemainingMeta(l10n, null), isNull);
    });

    test('ended deadline is urgent', () {
      final endAt = DateTime.now().subtract(const Duration(minutes: 5));
      final meta = beaconCardDeadlineRemainingMeta(l10n, endAt);
      expect(meta?.text, l10n.inboxDeadlineEnded);
      expect(meta?.urgent, isTrue);
    });

    test('under one hour is urgent', () {
      final endAt = DateTime.now().add(const Duration(minutes: 30));
      final meta = beaconCardDeadlineRemainingMeta(l10n, endAt);
      expect(meta?.text, l10n.inboxDeadlineLessThanHour);
      expect(meta?.urgent, isTrue);
    });

    test('multi-day remaining shows days and hours', () {
      final endAt = DateTime.now().add(const Duration(days: 2, hours: 5));
      final meta = beaconCardDeadlineRemainingMeta(l10n, endAt);
      final remaining = endAt.difference(DateTime.now());
      expect(
        meta?.text,
        l10n.inboxDeadlineDaysHoursRemaining(
          remaining.inDays,
          remaining.inHours % 24,
        ),
      );
      expect(meta?.urgent, isFalse);
    });
  });

  group('compactDeadlineLabel', () {
    test('returns null when endAt is null', () {
      expect(compactDeadlineLabel(l10n, null), isNull);
    });

    test('under one hour uses pill under-hour copy', () {
      final endAt = DateTime.now().add(const Duration(minutes: 20));
      final label = compactDeadlineLabel(l10n, endAt);
      expect(label?.text, l10n.inboxDeadlinePillUnderHour);
      expect(label?.urgent, isTrue);
    });

    test('multi-day remaining uses day pill', () {
      final endAt = DateTime.now().add(const Duration(days: 31));
      final label = compactDeadlineLabel(l10n, endAt);
      final days = endAt.difference(DateTime.now()).inDays;
      expect(label?.text, l10n.inboxDeadlinePillDays(days));
      expect(label?.urgent, isFalse);
    });
  });
}
