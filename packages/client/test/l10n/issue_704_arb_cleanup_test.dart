// Issue #704: drop two unused ARB keys and fix the RU plural for
// beaconShowcaseTeamNoAcquaintancesClosed (`=1` overlapped `one`).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/ui/l10n/l10n.dart';

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

const _locales = ['en', 'ru'];
const _removedKeys = [
  'beaconForwardsRecipientsMoved',
  'beaconLobbyBanConfirmBody',
];
const _ruClosedKey = 'beaconShowcaseTeamNoAcquaintancesClosed';

void main() {
  test('unused keys are gone from every ARB, metadata included', () {
    for (final locale in _locales) {
      final arb = _arb(locale);
      for (final key in _removedKeys) {
        expect(arb.containsKey(key), isFalse, reason: 'app_$locale.arb: $key');
        expect(
          arb.containsKey('@$key'),
          isFalse,
          reason: 'app_$locale.arb: @$key',
        );
      }
    }
  });

  test('no ARB plural pairs an exact =1 case with the one category', () {
    final overlap = RegExp(r'=1\{');
    final one = RegExp(r'(^|[\s{}])one\{');
    for (final locale in _locales) {
      final offenders = _arb(locale).entries
          .where((e) => !e.key.startsWith('@') && e.value is String)
          .where((e) {
            final value = e.value as String;
            return overlap.hasMatch(value) && one.hasMatch(value);
          })
          .map((e) => e.key)
          .toList();
      expect(offenders, isEmpty, reason: 'app_$locale.arb');
    }
  });

  test('RU closed team caption uses one, few, many and other forms', () {
    final value = _arb('ru')[_ruClosedKey] as String;
    expect(value, isNot(contains('=1{')));
    for (final form in ['one{', 'few{', 'many{', 'other{']) {
      expect(value, contains(form));
    }
  });

  test('RU closed team caption agrees with the count', () {
    final l10n = lookupL10n(const Locale('ru'));
    final expected = {
      1: 'Помог 1 человек',
      3: 'Помогли 3 человека',
      5: 'Помогли 5 человек',
      11: 'Помогли 11 человек',
      21: 'Помог 21 человек',
      22: 'Помогли 22 человека',
    };
    expected.forEach((count, text) {
      expect(l10n.beaconShowcaseTeamNoAcquaintancesClosed(count), text);
    });
  });
}
