import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Run from packages/client: the ARB files are read by relative path.
void main() {
  late Map<String, dynamic> en;
  late Map<String, dynamic> ru;

  setUpAll(() {
    en =
        jsonDecode(File('l10n/app_en.arb').readAsStringSync())
            as Map<String, dynamic>;
    ru =
        jsonDecode(File('l10n/app_ru.arb').readAsStringSync())
            as Map<String, dynamic>;
  });

  for (final key in ['graphTrustNotSaved', 'graphTrustRetry']) {
    test('$key has copy in both locales', () {
      expect(en[key], isA<String>());
      expect(ru[key], isA<String>());
      expect((en[key] as String).trim(), isNotEmpty);
      expect((ru[key] as String).trim(), isNotEmpty);
    });
  }

  test('the English copy says the trust change was not saved', () {
    expect(en['graphTrustNotSaved'], 'Trust change not saved');
    expect(en['graphTrustRetry'], 'Retry');
  });
}
