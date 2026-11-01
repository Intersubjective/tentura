import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/relative_time.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

void main() {
  late L10n ru;
  late L10n en;
  final now = DateTime(2026, 10, 11, 12);

  setUpAll(() async {
    await initializeDateFormatting('ru');
    await initializeDateFormatting('en');
    ru = await L10n.delegate.load(const Locale('ru'));
    en = await L10n.delegate.load(const Locale('en'));
  });

  String age(L10n l10n, Duration ago) =>
      cardRelativeAge(when: now.subtract(ago), now: now, l10n: l10n);

  test('RU card ages are short and never say «назад»', () {
    expect(age(ru, const Duration(seconds: 10)), 'сейчас');
    expect(age(ru, const Duration(minutes: 40)), '40 мин');
    expect(age(ru, const Duration(hours: 2)), '2 ч');
    expect(age(ru, const Duration(days: 3)), '3 дн.');
    expect(age(ru, const Duration(days: 30)), 'пт, 11 сент.');
    expect(age(ru, const Duration(days: 400)), 'сб, 6 сент. 2025\u202Fг.');
  });

  test('EN card ages', () {
    expect(age(en, const Duration(seconds: 10)), 'now');
    expect(age(en, const Duration(minutes: 40)), '40m');
    expect(age(en, const Duration(hours: 2)), '2h');
    expect(age(en, const Duration(days: 3)), '3d');
    expect(age(en, const Duration(days: 30)), 'Fri, Sep 11');
    expect(age(en, const Duration(days: 400)), 'Sat, Sep 6, 2025');
  });

  test('#609: past a week it is the #450 weekday day, with the year only '
      'for an earlier year — never a numeric yMd date', () {
    final when = DateTime(2025, 3, 4, 9);
    expect(
      cardRelativeAge(when: when, now: now, l10n: ru),
      'вт, 4 мар. 2025\u202Fг.',
    );
    expect(cardRelativeAge(when: when, now: now, l10n: en), 'Tue, Mar 4, 2025');
    expect(
      cardRelativeAge(when: when, now: now, l10n: en),
      dateFormatDay(when, locale: 'en', now: now),
    );
    expect(
      cardRelativeAge(when: when, now: now, l10n: en),
      isNot(DateFormat.yMd('en').format(when)),
    );
    // The QA repro: a card from Oct 31 read in January of the next year.
    final oct31 = DateTime(2026, 10, 31, 23, 10);
    final jan20 = DateTime(2027, 1, 20, 12);
    expect(
      cardRelativeAge(when: oct31, now: jan20, l10n: en),
      'Sat, Oct 31, 2026',
    );
    expect(
      cardRelativeAge(when: oct31, now: jan20, l10n: ru),
      'сб, 31 окт. 2026\u202Fг.',
    );
    // Past a week the spoken form is the same date the eye reads.
    expect(
      cardRelativeAgeSpoken(when: when, now: now, l10n: ru),
      'вт, 4 мар. 2025\u202Fг.',
    );
    expect(
      cardRelativeAgeSpoken(when: oct31, now: jan20, l10n: en),
      'Sat, Oct 31, 2026',
    );
  });

  test('the spoken form is the long one, with RU plurals', () {
    String spoken(int minutes) => cardRelativeAgeSpoken(
      when: now.subtract(Duration(minutes: minutes)),
      now: now,
      l10n: ru,
    );
    expect(spoken(1), '1 минуту назад');
    expect(spoken(2), '2 минуты назад');
    expect(spoken(5), '5 минут назад');
    expect(spoken(11), '11 минут назад');
    expect(spoken(21), '21 минуту назад');
    expect(spoken(22), '22 минуты назад');
    expect(spoken(25), '25 минут назад');
  });
}
