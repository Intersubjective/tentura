import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _keys = [
  'constellationPlacementNotSaved',
  'constellationPlacementRetry',
  'constellationPlacementDiscard',
  'constellationPlacementSaving',
];

Map<String, dynamic> _arb(File file) =>
    jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

void main() {
  final arbFiles = Directory('l10n')
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.arb'))
      .toList();

  test('the placement marker strings exist in every ARB file', () {
    expect(arbFiles, isNotEmpty);
    for (final file in arbFiles) {
      final arb = _arb(file);
      for (final key in _keys) {
        expect(
          arb[key],
          isA<String>().having((s) => s.trim(), 'text', isNotEmpty),
          reason: '${file.path} is missing $key',
        );
        if (file.path.endsWith('app_en.arb')) {
          expect(arb['@$key'], isNotNull, reason: '${file.path} lacks @$key');
        }
      }
    }
  });
}
