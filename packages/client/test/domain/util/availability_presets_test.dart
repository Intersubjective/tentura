import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/util/availability_presets.dart';
import 'package:tentura_root/domain/availability.dart';

void main() {
  final today = DateTime.utc(2026, 3, 2); // Monday

  group('availabilityTomorrowPreset', () {
    test('adds one calendar day', () {
      expect(availabilityTomorrowPreset(today), DateTime.utc(2026, 3, 3));
    });
  });

  group('availabilityThisWeekendPreset', () {
    test('Monday maps to following Monday', () {
      expect(availabilityThisWeekendPreset(today), DateTime.utc(2026, 3, 9));
    });

    test('Sunday maps to next Monday', () {
      final sunday = DateTime.utc(2026, 3, 8);
      expect(availabilityThisWeekendPreset(sunday), DateTime.utc(2026, 3, 9));
    });

    test('Saturday maps to next Monday', () {
      final saturday = DateTime.utc(2026, 3, 7);
      expect(availabilityThisWeekendPreset(saturday), DateTime.utc(2026, 3, 9));
    });
  });

  group('availabilityOneWeekPreset', () {
    test('adds seven calendar days', () {
      expect(availabilityOneWeekPreset(today), DateTime.utc(2026, 3, 9));
    });
  });

  group('availabilityOneMonthPreset', () {
    test('clamps Jan 31 to Feb 28 in a non-leap year', () {
      final jan31 = DateTime.utc(2025, 1, 31);
      expect(availabilityOneMonthPreset(jan31), DateTime.utc(2025, 2, 28));
    });

    test('clamps Jan 31 to Feb 29 in a leap year', () {
      final jan31 = DateTime.utc(2024, 1, 31);
      expect(availabilityOneMonthPreset(jan31), DateTime.utc(2024, 2, 29));
    });

    test('preserves day when target month is long enough', () {
      final mar15 = DateTime.utc(2026, 3, 15);
      expect(availabilityOneMonthPreset(mar15), DateTime.utc(2026, 4, 15));
    });

    test('rolls year when needed', () {
      final dec10 = DateTime.utc(2026, 12, 10);
      expect(availabilityOneMonthPreset(dec10), DateTime.utc(2027, 1, 10));
    });
  });

  group('availabilityMaxResumeOn', () {
    test('is today plus ninety calendar days', () {
      expect(
        availabilityMaxResumeOn(today),
        DateTime.utc(2026, 5, 31),
      );
    });
  });

  group('availabilityTodayUtc', () {
    test('uses UTC y/m/d from clock', () {
      final clock = () => DateTime.utc(2026, 8, 14, 23, 45);
      expect(availabilityTodayUtc(clock), DateTime.utc(2026, 8, 14));
    });

    test('uses UTC calendar date when clock is local evening', () {
      final clock = () => DateTime(2026, 8, 14, 23, 45);
      expect(availabilityTodayUtc(clock), DateTime.utc(2026, 8, 14));
    });

    test('uses the preceding UTC date across an explicit offset midnight', () {
      final clock = () => DateTime.parse('2026-08-14T00:15:00+02:00');
      expect(availabilityTodayUtc(clock), DateTime.utc(2026, 8, 13));
    });
  });

  group('utcCalendarDateFromLocalPicker', () {
    test('uses picker y/m/d as UTC calendar date', () {
      final picked = DateTime(2026, 8, 18);
      expect(
        utcCalendarDateFromLocalPicker(picked),
        DateTime.utc(2026, 8, 18),
      );
      expect(isUtcCalendarDate(utcCalendarDateFromLocalPicker(picked)), isTrue);
    });
  });
}
