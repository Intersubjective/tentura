// The typing indicator's copy ("Ben is typing…", "N people are typing…") must
// live in the ARB files, in every locale the app ships (en, ru). Messages are
// found by their content (they talk about typing), so the test does not depend
// on key names.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

/// Keys of the messages (not `@meta`) whose English text is about typing.
Map<String, String> _typingMessages(String locale, Iterable<String> keys) {
  final arb = _arb(locale);
  return {for (final k in keys) k: arb[k]! as String};
}

List<String> _typingKeysInEnglish() {
  final en = _arb('en');
  return [
    for (final e in en.entries)
      if (!e.key.startsWith('@') &&
          e.value is String &&
          (e.value as String).toLowerCase().contains('typing'))
        e.key,
  ];
}

final _plural = RegExp(r'^\{(\w+),\s*plural,');

bool _isPlural(String message) => _plural.hasMatch(message.trim());

void main() {
  group('typing indicator copy in the ARB files', () {
    test('English has a one-person line and a counted plural line', () {
      final keys = _typingKeysInEnglish();
      final messages = _typingMessages('en', keys).values.toList();

      expect(
        messages.where((m) => !_isPlural(m) && RegExp(r'\{\w+\}').hasMatch(m)),
        isNotEmpty,
        reason: 'a message names the typist: "{name} is typing…"',
      );
      expect(
        messages.where(_isPlural),
        isNotEmpty,
        reason: 'a plural message counts typists: "{count} people …"',
      );
    });

    test('Russian has the same keys, translated, with Russian plurals', () {
      final keys = _typingKeysInEnglish();
      expect(keys, isNotEmpty);
      final en = _typingMessages('en', keys);
      final ru = _arb('ru');

      for (final key in keys) {
        final value = ru[key];
        expect(value, isA<String>(), reason: 'app_ru.arb lacks $key');
        expect(value, isNot(en[key]), reason: '$key is not translated');
        expect(
          value as String,
          matches(RegExp('[а-яА-Я]')),
          reason: '$key is not Russian',
        );
        if (_isPlural(en[key]!)) {
          expect(_isPlural(value), isTrue, reason: '$key must stay a plural');
          expect(value, contains('few{'), reason: 'Russian needs «few»');
          expect(value, contains('many{'), reason: 'Russian needs «many»');
          expect(value, contains('other{'));
        }
      }
    });

    test('every typing message is documented with a description', () {
      final arb = _arb('en');
      final keys = _typingKeysInEnglish();
      expect(keys, isNotEmpty, reason: 'no typing messages in app_en.arb');
      for (final key in keys) {
        final meta = arb['@$key'];
        expect(meta, isA<Map<String, dynamic>>(), reason: '@$key missing');
        expect(
          (meta as Map)['description'],
          isA<String>(),
          reason: '@$key needs a description',
        );
      }
    });
  });
}
