import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:tentura/ui/utils/schedule_date_format.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
  });

  const localeName = 'en';
  final now = DateTime(2026, 6, 15, 12);

  group('formatScheduleDate', () {
    test('same year omits year', () {
      expect(
        formatScheduleDate(
          DateTime(2026, 6, 20),
          localeName: localeName,
          now: now,
        ),
        'Jun 20',
      );
    });

    test('different year includes year', () {
      expect(
        formatScheduleDate(
          DateTime(2027, 5, 8),
          localeName: localeName,
          now: now,
        ),
        'May 8, 2027',
      );
    });
  });

  group('formatScheduleRange', () {
    test('same calendar day collapses to single date', () {
      expect(
        formatScheduleRange(
          DateTime(2026, 6, 20, 9),
          DateTime(2026, 6, 20, 17),
          localeName: localeName,
          now: now,
        ),
        'Jun 20',
      );
    });

    test('multi-day range joins both sides', () {
      expect(
        formatScheduleRange(
          DateTime(2026, 6, 20),
          DateTime(2026, 6, 23),
          localeName: localeName,
          now: now,
        ),
        'Jun 20 – Jun 23',
      );
    });

    test('cross-year range adds year only on dates outside current year', () {
      expect(
        formatScheduleRange(
          DateTime(2026, 12, 30),
          DateTime(2027, 1, 2),
          localeName: localeName,
          now: now,
        ),
        'Dec 30 – Jan 2, 2027',
      );
    });
  });
}
