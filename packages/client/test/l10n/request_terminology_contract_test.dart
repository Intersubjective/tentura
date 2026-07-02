import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

void main() {
  final enArb = jsonDecode(
    File('l10n/app_en.arb').readAsStringSync(),
  ) as Map<String, dynamic>;
  final ruArb = jsonDecode(
    File('l10n/app_ru.arb').readAsStringSync(),
  ) as Map<String, dynamic>;

  test('ARB values do not use internal beacon/room product nouns', () {
    for (final entry in enArb.entries) {
      if (entry.key.startsWith('@') || entry.value is! String) {
        continue;
      }
      final v = entry.value as String;
      expect(
        RegExp(r'\b[Bb]eacon\b|\bbeacons\b|\bBeacons\b').hasMatch(v),
        isFalse,
        reason: 'app_en.arb ${entry.key}',
      );
      expect(
        RegExp(r'\b[Rr]oom\b|\broom\b').hasMatch(v),
        isFalse,
        reason: 'app_en.arb ${entry.key} room',
      );
    }
    for (final entry in ruArb.entries) {
      if (entry.key.startsWith('@') || entry.value is! String) {
        continue;
      }
      final v = entry.value as String;
      expect(
        RegExp('маяк', caseSensitive: false).hasMatch(v),
        isFalse,
        reason: 'app_ru.arb ${entry.key}',
      );
      expect(
        RegExp('комнат', caseSensitive: false).hasMatch(v),
        isFalse,
        reason: 'app_ru.arb ${entry.key} room',
      );
    }
  });

  test('core labels use Request / запрос', () {
    final en = L10nEn();
    final ru = L10nRu();
    expect(en.beaconsTitle.toLowerCase(), contains('request'));
    expect(en.beaconViewTitle.toLowerCase(), contains('request'));
    expect(en.myWorkEmptyActiveCreateCta.toLowerCase(), contains('request'));
    expect(ru.beaconsTitle.toLowerCase(), contains('запрос'));
  });
}
