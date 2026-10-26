import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _arb(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  final en = _arb('l10n/app_en.arb');
  final ru = _arb('l10n/app_ru.arb');

  group('people tag suggestion opt-out copy', () {
    test('the card action reads "Don\'t suggest again" in English', () {
      expect(en['peopleTagsDontSuggest'], "Don't suggest again");
    });

    test('the card action reads «Больше не предлагать» in Russian', () {
      expect(ru['peopleTagsDontSuggest'], 'Больше не предлагать');
    });

    test('the People tags switch reads "Suggest tags" in English', () {
      expect(en['peopleTagsSuggestEnable'], 'Suggest tags');
    });

    test('the People tags switch reads «Предлагать теги» in Russian', () {
      expect(ru['peopleTagsSuggestEnable'], 'Предлагать теги');
    });
  });
}
