import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Undo snackbar after «Tidy up» tells how many people moved.

Map<String, dynamic> _arb(String name) =>
    jsonDecode(File('l10n/$name.arb').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  group('tidy up snackbar copy', () {
    test('English text names the number of people moved', () {
      expect(
        _arb('app_en')['constellationTidied'],
        'Tidied up: {n} people moved',
      );
    });

    test('Russian text names the number of people moved', () {
      expect(_arb('app_ru')['constellationTidied'], 'Причёсано: сдвинуто {n}');
    });

    test('the count is a numeric placeholder named n', () {
      final meta =
          _arb('app_en')['@constellationTidied'] as Map<String, dynamic>?;

      expect(meta?['placeholders'], contains('n'));
    });
  });
}
