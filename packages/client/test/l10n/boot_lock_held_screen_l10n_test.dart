import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The startup screen shown when another Tentura tab holds the local database
// has its own title, body and Reload label in both languages, distinct from
// the generic startup-failure strings.
//
// Run from packages/client: the ARB files are read by relative path.
Map<String, dynamic> _arb(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

const _keys = ['bootLockHeldTitle', 'bootLockHeldBody', 'bootLockHeldReload'];

final _cyrillic = RegExp('[А-Яа-яЁё]');

void main() {
  group('startup screen for a database held by another tab: ARB strings', () {
    final en = _arb('l10n/app_en.arb');
    final ru = _arb('l10n/app_ru.arb');

    test('every key exists in English and Russian with non-empty text', () {
      for (final key in _keys) {
        expect(en[key], isA<String>(), reason: 'app_en.arb lacks $key');
        expect(ru[key], isA<String>(), reason: 'app_ru.arb lacks $key');
        expect((en[key] as String).trim(), isNotEmpty, reason: key);
        expect((ru[key] as String).trim(), isNotEmpty, reason: key);
      }
    });

    test('English body tells the user to close other Tentura tabs', () {
      expect(
        (en['bootLockHeldBody'] as String?)?.toLowerCase(),
        contains('close other tentura tabs'),
      );
    });

    test('Russian strings are Russian, not the English copy', () {
      for (final key in _keys) {
        expect(ru[key], contains(_cyrillic), reason: key);
        expect(ru[key], isNot(en[key]), reason: key);
      }
    });

    test('the strings differ from the generic startup failure', () {
      for (final arb in [en, ru]) {
        expect(arb['bootLockHeldTitle'], isA<String>());
        expect(arb['bootLockHeldBody'], isA<String>());
        expect(arb['bootLockHeldTitle'], isNot(arb['bootFailureTitle']));
        expect(arb['bootLockHeldBody'], isNot(arb['bootFailureBodyWeb']));
      }
    });
  });
}
