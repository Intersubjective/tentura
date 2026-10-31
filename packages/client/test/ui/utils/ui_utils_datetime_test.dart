import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ru');
  });

  test('dateFormatDay/timeFormatHm always render viewer-local time', () {
    final utcInstant = DateTime.utc(2026, 6, 20, 23, 30);
    final local = utcInstant.toLocal();
    expect(
      dateFormatDay(utcInstant, locale: 'en', now: local),
      DateFormat.MMMEd('en').format(local),
    );
    expect(timeFormatHm(utcInstant), DateFormat.Hm().format(local));
  });

  test('null input is empty string', () {
    expect(dateFormatDay(null, locale: 'ru'), '');
    expect(timeFormatHm(null), '');
  });

  // #450 (#609 follow-up): a day reads «Sat, Oct 17» with its weekday, in
  // the app language, never a numeric 10/17/2026 or 17.10.2026.
  group('#450 dateFormatDay: weekday style in the app language', () {
    final day = DateTime(2026, 10, 17, 18, 40);
    final now = DateTime(2026, 10, 31, 12);

    test('en reads «Sat, Oct 17»', () {
      expect(dateFormatDay(day, locale: 'en', now: now), 'Sat, Oct 17');
    });

    test('ru reads «сб, 17 окт.»', () {
      expect(dateFormatDay(day, locale: 'ru', now: now), 'сб, 17 окт.');
    });

    test('another year carries the year', () {
      final old = DateTime(2025, 3, 4, 9);
      expect(dateFormatDay(old, locale: 'en', now: now), 'Tue, Mar 4, 2025');
      // intl separates «2025 г.» with a no-break space.
      expect(
        dateFormatDay(
          old,
          locale: 'ru',
          now: now,
        ).replaceAll(RegExp('[\u00A0\u202F]'), ' '),
        'вт, 4 мар. 2025 г.',
      );
    });

    test('the locale is the given one, not the process default', () {
      final saved = Intl.defaultLocale;
      addTearDown(() => Intl.defaultLocale = saved);
      Intl.defaultLocale = 'en';
      expect(dateFormatDay(day, locale: 'ru', now: now), 'сб, 17 окт.');
      Intl.defaultLocale = 'ru';
      expect(dateFormatDay(day, locale: 'en', now: now), 'Sat, Oct 17');
    });
  });

  group('#670 timeFormatHm follows the app locale', () {
    final day = DateTime(2026, 10, 5, 8, 40);

    setUpAll(() async {
      await initializeDateFormatting('da');
    });

    test('ru reads HH:mm', () {
      expect(timeFormatHm(day, locale: 'ru'), '08:40');
    });

    test('the pattern comes from the given locale, not the default', () {
      final saved = Intl.defaultLocale;
      addTearDown(() => Intl.defaultLocale = saved);
      Intl.defaultLocale = 'en';
      // Danish writes the time with a dot; en and ru both use a colon.
      expect(timeFormatHm(day, locale: 'da'), '08.40');
      expect(timeFormatHm(day, locale: 'ru'), '08:40');
      expect(timeFormatHm(null, locale: 'ru'), '');
    });
  });
}
