import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/relative_time.dart';

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
    expect(age(ru, const Duration(days: 30)), '11 сент.');
    expect(age(ru, const Duration(days: 400)), '06.09.25');
  });

  test('EN card ages', () {
    expect(age(en, const Duration(seconds: 10)), 'now');
    expect(age(en, const Duration(minutes: 40)), '40m');
    expect(age(en, const Duration(hours: 2)), '2h');
    expect(age(en, const Duration(days: 3)), '3d');
    expect(age(en, const Duration(days: 30)), 'Sep 11');
    expect(age(en, const Duration(days: 400)), '9/6/25');
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
