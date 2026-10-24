import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Run from packages/client: the ARB files are read by relative path.
void main() {
  for (final locale in ['en', 'ru']) {
    group('$locale copy of the tag drop confirmation', () {
      late Map<String, dynamic> arb;

      setUpAll(() {
        arb =
            jsonDecode(File('l10n/app_$locale.arb').readAsStringSync())
                as Map<String, dynamic>;
      });

      test('peopleTagsDroppedOnChip has a message', () {
        final message = arb['peopleTagsDroppedOnChip'];
        expect(message, isA<String>());
        expect((message as String).trim(), isNotEmpty);
      });
    });
  }

  test('the English message says where the person was added', () {
    final arb =
        jsonDecode(File('l10n/app_en.arb').readAsStringSync())
            as Map<String, dynamic>;
    final message = arb['peopleTagsDroppedOnChip'] as String?;
    final meta = arb['@peopleTagsDroppedOnChip'] as Map<String, dynamic>?;

    expect(message, isNotNull);
    expect(message, contains('{'), reason: 'it names the tag by placeholder');
    expect(meta?['placeholders'], isNotEmpty);
  });
}
