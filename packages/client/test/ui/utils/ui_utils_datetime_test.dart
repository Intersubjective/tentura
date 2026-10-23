import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ru');
  });

  test('dateFormatYMD/timeFormatHm always render viewer-local time', () {
    final utcInstant = DateTime.utc(2026, 6, 20, 23, 30);
    final local = utcInstant.toLocal();
    expect(dateFormatYMD(utcInstant), DateFormat.yMd().format(local));
    expect(timeFormatHm(utcInstant), DateFormat.Hm().format(local));
  });

  test('null input is empty string', () {
    expect(dateFormatYMD(null), '');
    expect(dateFormatYMD(null, locale: 'ru'), '');
    expect(timeFormatHm(null), '');
  });

  group('#609 dateFormatYMD follows the app locale', () {
    final day = DateTime(2026, 10, 5, 18, 40);

    test('ru reads dd.MM.yyyy', () {
      expect(dateFormatYMD(day, locale: 'ru'), '05.10.2026');
    });

    test('en keeps M/d/yyyy', () {
      expect(dateFormatYMD(day, locale: 'en'), '10/5/2026');
    });

    test('ru does not depend on the process default locale', () {
      final saved = Intl.defaultLocale;
      addTearDown(() => Intl.defaultLocale = saved);
      Intl.defaultLocale = 'en';
      expect(dateFormatYMD(day, locale: 'ru'), '05.10.2026');
      Intl.defaultLocale = 'ru';
      expect(dateFormatYMD(day, locale: 'en'), '10/5/2026');
    });
  });
}
