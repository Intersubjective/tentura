import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _arb(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  test('en and ru ARB files keep the same message keys', () {
    Set<String> keys(String p) =>
        _arb(p).keys.where((k) => !k.startsWith('@')).toSet();
    final en = keys('l10n/app_en.arb');
    final ru = keys('l10n/app_ru.arb');
    expect(en.difference(ru), isEmpty);
    expect(ru.difference(en), isEmpty);
  });
}
