import 'package:tentura_root/domain/availability.dart';
import 'package:tentura_root/domain/enums.dart';
import 'package:test/test.dart';

DateTime _utcDate(int year, int month, int day) => DateTime.utc(year, month, day);

void main() {
  group('utcCalendarDate', () {
    test('normalizes UTC instants to UTC midnight', () {
      expect(
        utcCalendarDate(DateTime.utc(2026, 8, 13, 15, 30)),
        _utcDate(2026, 8, 13),
      );
    });

    test('uses UTC components regardless of local DateTime construction', () {
      // Local midnight for 2026-08-13 in a positive-offset zone is still the
      // prior UTC day; utcCalendarDate must follow UTC, not local calendar day.
      final localMidnight = DateTime(2026, 8, 13);
      final normalized = utcCalendarDate(localMidnight);
      final utcMidnight = DateTime.utc(
        localMidnight.toUtc().year,
        localMidnight.toUtc().month,
        localMidnight.toUtc().day,
      );
      expect(normalized, utcMidnight);
      expect(isUtcCalendarDate(normalized), isTrue);
    });
  });

  group('isUtcCalendarDate', () {
    test('accepts UTC midnight', () {
      expect(isUtcCalendarDate(_utcDate(2026, 8, 13)), isTrue);
    });

    test('rejects non-midnight and non-UTC values', () {
      expect(isUtcCalendarDate(DateTime.utc(2026, 8, 13, 1)), isFalse);
      expect(isUtcCalendarDate(DateTime(2026, 8, 13)), isFalse);
    });
  });

  group('availabilityViewOn', () {
    final todayUtc = _utcDate(2026, 8, 13);

    test('open when absent fields', () {
      expect(
        availabilityViewOn(isLimited: false, todayUtc: todayUtc),
        AvailabilityView.open,
      );
    });

    test('limited when isLimited and no pause', () {
      expect(
        availabilityViewOn(isLimited: true, todayUtc: todayUtc),
        AvailabilityView.limited,
      );
    });

    test('paused when resumeOn is in the future', () {
      expect(
        availabilityViewOn(
          isLimited: false,
          resumeOn: _utcDate(2026, 8, 18),
          todayUtc: todayUtc,
        ),
        AvailabilityView.paused,
      );
    });

    test('available on resume day (equality boundary)', () {
      expect(
        availabilityViewOn(
          isLimited: false,
          resumeOn: todayUtc,
          todayUtc: todayUtc,
        ),
        AvailabilityView.open,
      );
    });

    test('open when pause is in the past', () {
      expect(
        availabilityViewOn(
          isLimited: false,
          resumeOn: _utcDate(2026, 8, 12),
          todayUtc: todayUtc,
        ),
        AvailabilityView.open,
      );
    });

    test('limited+future pause is paused', () {
      expect(
        availabilityViewOn(
          isLimited: true,
          resumeOn: _utcDate(2026, 8, 20),
          todayUtc: todayUtc,
        ),
        AvailabilityView.paused,
      );
    });

    test('limited+past pause falls back to limited', () {
      expect(
        availabilityViewOn(
          isLimited: true,
          resumeOn: _utcDate(2026, 8, 10),
          todayUtc: todayUtc,
        ),
        AvailabilityView.limited,
      );
    });
  });
}
