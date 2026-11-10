// #1095: the Russian UI spells the brand one way, «Тентура», declined where
// the grammar needs a case ending. This guard reads app_ru.arb directly so a
// Latin «Tentura» in any user-visible RU value fails before it ships.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Latin spellings a RU value may still carry, and why each one has to stay
/// Latin. Empty today: no RU value needs the Latin brand. A domain such as
/// `tentura.io` is matched by [_latinRequired] instead, because a URL or a
/// host name is typed, not read, and must stay Latin.
const _allowedValues = <String, String>{};

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
  test('no RU ARB value carries the Latin brand «Tentura»', () {
    final offenders = <String>[
      for (final MapEntry(:key, :value) in _ruValues().entries)
        if (!_allowedValues.containsKey(key) &&
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
