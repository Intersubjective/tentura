// The typing indicator shows the text its ARB message says, in every locale
// the app ships (en, ru): one name uses the one-person message, several use
// the counted plural with each locale's plural form. The ARB content itself is
// pinned in room_typing_arb_copy_test.dart.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/profile.dart';

import '../features/beacon_threads/support/room_body_harness.dart';

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

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

/// Expands one `{n, plural, =1{..} one{..} few{..} other{..}}` message for
/// [count] using the CLDR rules of [locale] (en, ru), then fills `{n}`.
String _expandPlural(String message, int count, String locale) {
  final m = _plural.firstMatch(message.trim())!;
  final variable = m.group(1)!;
  var rest = message.trim().substring(m.end);
  rest = rest.substring(0, rest.lastIndexOf('}'));
  final branches = <String, String>{};
  var i = 0;
  while (i < rest.length) {
    while (i < rest.length && rest[i].trim().isEmpty) {
      i++;
    }
    final start = i;
    while (i < rest.length && rest[i] != '{') {
      i++;
    }
    final selector = rest.substring(start, i).trim();
    var depth = 0;
    final bodyStart = i + 1;
    do {
      if (rest[i] == '{') depth++;
      if (rest[i] == '}') depth--;
      i++;
    } while (depth > 0);
    branches[selector] = rest.substring(bodyStart, i - 1);
  }
  final category = switch (locale) {
    'ru' =>
      count % 10 == 1 && count % 100 != 11
          ? 'one'
          : (count % 10 >= 2 &&
                    count % 10 <= 4 &&
                    (count % 100 < 12 || count % 100 > 14)
                ? 'few'
                : 'many'),
    _ => count == 1 ? 'one' : 'other',
  };
  final chosen =
      branches['=$count'] ?? branches[category] ?? branches['other']!;
  return chosen.replaceAll('{$variable}', '$count');
}

String _fillName(String message, String name) =>
    message.replaceAll(RegExp(r'\{\w+\}'), name);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the indicator shows what the ARB says', () {
    final keys = _typingKeysInEnglish();

    for (final locale in ['en', 'ru']) {
      final one = keys.firstWhere(
        (k) => !_isPlural(_arb('en')[k]! as String),
        orElse: () => '',
      );
      final counted = keys.firstWhere(
        (k) => _isPlural(_arb('en')[k]! as String),
        orElse: () => '',
      );
      final name = locale == 'ru' ? 'Бен' : 'Ben';
      final typist = Profile(id: 'u-ben', displayName: name);

      testWidgets('one typist in $locale uses the one-person message', (
        tester,
      ) async {
        expect(one, isNotEmpty, reason: 'no one-person message in the ARB');
        final expected = _fillName(_arb(locale)[one]! as String, name);
        await pumpBeaconRoomBody(
          tester,
          locale: Locale(locale),
          roomState: roomBodyState().copyWith(
            participants: [
              roomBodyAdmittedParticipant(beaconId: 'b1', profile: typist),
            ],
            participantsLoaded: true,
            typingUserIds: [typist.id],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(expected), findsOneWidget);
      });

      for (final count in locale == 'ru' ? [2, 5, 21] : [2, 7]) {
        testWidgets('$count typists in $locale use the counted message', (
          tester,
        ) async {
          expect(counted, isNotEmpty, reason: 'no counted message in the ARB');
          final expected = _expandPlural(
            _arb(locale)[counted]! as String,
            count,
            locale,
          );
          await pumpBeaconRoomBody(
            tester,
            locale: Locale(locale),
            roomState: roomBodyState().copyWith(
              typingUserIds: [for (var i = 0; i < count; i++) 'u-$i'],
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text(expected), findsOneWidget);
        });
      }
    }
  });
}
