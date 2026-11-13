// Every user-facing string of the «brought a fact» feature lives in both
// ARBs (EN wording is the contract; RU must be real Russian, with ICU
// plurals where a count is shown) and the widgets carry no hard-coded copy.
// Run from packages/client (reads l10n/ and lib/ by relative path).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _arb(String name) =>
    jsonDecode(File('l10n/$name').readAsStringSync()) as Map<String, dynamic>;

final _cyrillic = RegExp('[А-Яа-яЁё]');

void main() {
  final en = _arb('app_en.arb');
  final ru = _arb('app_ru.arb');

  String? keyOf(bool Function(String v) test) {
    for (final e in en.entries) {
      if (!e.key.startsWith('@') &&
          e.value is String &&
          test(e.value as String)) {
        return e.key;
      }
    }
    return null;
  }

  final required = <String, RegExp>{
    'single fact from a Request': RegExp(
      r'^\{\w+\} brought a fact from another Request$',
    ),
    'single fact from a Post': RegExp(
      r'^\{\w+\} brought a fact from another Post$',
    ),
    'several facts from a Request': RegExp(
      r'^\{\w+, plural,.*\{\w+\} facts from another Request\}',
    ),
    'several facts from a Post': RegExp(
      r'^\{\w+, plural,.*\{\w+\} facts from another Post\}',
    ),
    'history «brought this here»': RegExp(r'^\{\w+\} brought this here$'),
  };

  group('brought-a-fact strings exist in both ARBs', () {
    required.forEach((label, pattern) {
      test('$label has an EN key and a Russian translation', () {
        final key = keyOf(pattern.hasMatch);
        expect(key, isNotNull, reason: 'no EN string for: $label');
        final ruValue = ru[key];
        expect(ruValue, isA<String>(), reason: '$key missing in app_ru.arb');
        expect(ruValue as String, matches(_cyrillic));
        expect(ruValue, isNot(contains('brought')));
        if ((en[key] as String).contains('plural')) {
          for (final form in ['one', 'few', 'many']) {
            expect(ruValue, contains('$form{'), reason: '$key lacks $form');
          }
        }
      });
    });
  });

  test('every EN string has a Russian counterpart (no feature string is '
      'left untranslated)', () {
    final missing = [
      for (final k in en.keys)
        if (!k.startsWith('@') && !ru.containsKey(k)) k,
    ];
    expect(missing, isEmpty);
  });
}
