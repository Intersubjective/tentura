// Issue #178 part 2: the offerer's pending-offer status uses the approved
// author-seen wording in both supported locales.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

const _pendingCopy = <String>[
  'Sent · not seen by the author yet',
  'Seen by the author · awaiting decision',
];

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  for (final englishCopy in _pendingCopy) {
    test('pending offer localizes "$englishCopy" exactly once', () {
      final englishKeys = _arb('en').entries
          .where((entry) => !entry.key.startsWith('@'))
          .where((entry) => entry.value == englishCopy)
          .map((entry) => entry.key)
          .toList();

      expect(
        englishKeys,
        hasLength(1),
        reason: 'The approved English status needs one ARB message key',
      );

      final russianCopy = _arb('ru')[englishKeys.single];
      expect(russianCopy, isA<String>());
      expect((russianCopy as String).trim(), isNotEmpty);
      expect(russianCopy, isNot(englishCopy));
    });
  }
}
