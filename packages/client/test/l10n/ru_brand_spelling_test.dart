// #1095: Russian UI copy uses the declined form of «Тентура» where needed.
// The People section heading has its own exact spelling in the acceptance
// criteria. Check the catalogs directly to keep that exception local.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Exact key and value of the People section heading from the #781 plan.
const _allowedValues = {'peopleWithoutAccounts': 'Ещё не в Tentura'};

/// URLs and domain names: these are Latin by necessity (`tentura.io`,
/// `https://…tentura…`), so they are cut out before the brand check.
final _latinRequired = RegExp(
  r'(https?://\S+|[\w.-]*tentura\.(io|app|org|com)\S*)',
  caseSensitive: false,
);

/// Prepositions that never take the nominative: «в/к/о/для… Тентура» is
/// always a missing case ending («в Тентуре», «к Тентуре», «для Тентуры»).
final _undeclined = RegExp(
  r'(^|[\s«(])(в|во|к|ко|о|об|при|для|из|от|без|до|у)\s+Тентура(?![а-яё])',
  caseSensitive: false,
);

Map<String, String> _ruValues() {
  final raw =
      jsonDecode(File('l10n/app_ru.arb').readAsStringSync())
          as Map<String, dynamic>;
  return {
    for (final e in raw.entries)
      if (!e.key.startsWith('@') && e.value is String) e.key: e.value as String,
  };
}

void main() {
  test('the Latin brand exception is limited to the exact People heading', () {
    final values = _ruValues();
    for (final MapEntry(:key, :value) in _allowedValues.entries) {
      expect(values[key], value, reason: key);
    }
    final offenders = <String>[
      for (final MapEntry(:key, :value) in values.entries)
        if (_allowedValues[key] != value &&
            value
                .replaceAll(_latinRequired, '')
                .toLowerCase()
                .contains(
                  'tentura',
                ))
          '$key: $value',
    ];
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('RU brand after a preposition is declined («в Тентуре»)', () {
    final offenders = <String>[
      for (final MapEntry(:key, :value) in _ruValues().entries)
        if (_undeclined.hasMatch(value)) '$key: $value',
    ];
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('the guard itself spots Latin and undeclined forms', () {
    String strip(String v) => v.replaceAll(_latinRequired, '');
    expect(strip('В Tentura с 4 ноября').contains('Tentura'), isTrue);
    expect(
      strip('Откройте https://dev.tentura.io').contains('tentura'),
      isFalse,
    );
    expect(_undeclined.hasMatch('Добро пожаловать в Тентура'), isTrue);
    expect(_undeclined.hasMatch('С 4 ноября в Тентуре'), isFalse);
    expect(_undeclined.hasMatch('Тентура — это место'), isFalse);
  });
}
