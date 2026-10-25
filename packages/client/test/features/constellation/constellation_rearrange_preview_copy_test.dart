import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The «Rearrange everyone» preview tells how many people will move and that
/// the current layout is kept in history.

Map<String, dynamic> _arb(String name) =>
    jsonDecode(File('l10n/$name.arb').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  group('rearrange everyone preview copy', () {
    test(
      'English text names the people who will move and the saved layout',
      () {
        expect(
          _arb('app_en')['constellationRearrangePreview'],
          '{n} people will move · your current layout is saved to history',
        );
      },
    );

    test(
      'Russian text names the people who will move and the saved layout',
      () {
        expect(
          _arb('app_ru')['constellationRearrangePreview'],
          'Сдвинется {n} чел. · текущая расстановка сохранится в истории',
        );
      },
    );

    test('the count is a numeric placeholder named n', () {
      final meta =
          _arb('app_en')['@constellationRearrangePreview']
              as Map<String, dynamic>?;

      expect(meta?['placeholders'], contains('n'));
    });
  });
}
