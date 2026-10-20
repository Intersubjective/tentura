import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// #466: one name for the recovery secret ("recovery seed" /
// "seed восстановления"), and a warning that ships with the seed dialog.

Map<String, dynamic> _arb(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

Map<String, String> _messages(Map<String, dynamic> arb) => {
  for (final e in arb.entries)
    if (!e.key.startsWith('@') && e.value is String) e.key: e.value as String,
};

void main() {
  final en = _arb('l10n/app_en.arb');
  final ru = _arb('l10n/app_ru.arb');
  final enMsgs = _messages(en);
  final ruMsgs = _messages(ru);

  test('seed dialog warning exists in every ARB file', () {
    final arbFiles = Directory(
      'l10n',
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.arb'));
    for (final file in arbFiles) {
      final value = _arb(file.path)['seedDialogWarning'];
      expect(
        value,
        isA<String>().having((s) => s.trim(), 'text', isNotEmpty),
        reason: '${file.path} is missing seedDialogWarning',
      );
    }
    expect(en['@seedDialogWarning'], isNotNull);
  });

  test('EN warning says what it is and that anyone with it can sign in', () {
    final w = enMsgs['seedDialogWarning']!.toLowerCase();
    expect(w, contains('recovery seed'));
    expect(w, contains('anyone'));
    expect(w, contains('sign in'));
    expect(w, anyOf(contains('private'), contains('offline')));
  });

  test('RU warning uses the same name and warns about sign-in', () {
    final w = ruMsgs['seedDialogWarning']!.toLowerCase();
    expect(w, contains('seed восстановления'));
    expect(w, contains('люб'));
    expect(w, anyOf(contains('вой'), contains('вход')));
    expect(w, isNot(contains('seed-фраз')));
  });

  test('seed menu entry and copy snack use the one name', () {
    for (final key in ['showSeed', 'seedCopied']) {
      expect(
        enMsgs[key]!.toLowerCase(),
        contains('recovery seed'),
        reason: 'app_en.arb $key',
      );
      expect(
        ruMsgs[key]!.toLowerCase(),
        contains('seed восстановления'),
        reason: 'app_ru.arb $key',
      );
    }
  });

  test('no other name for the secret is left in the copy', () {
    for (final e in enMsgs.entries) {
      expect(
        e.value.toLowerCase(),
        isNot(contains('seed phrase')),
        reason: 'app_en.arb ${e.key}',
      );
    }
    for (final e in ruMsgs.entries) {
      expect(
        e.value.toLowerCase(),
        isNot(contains('seed-фраз')),
        reason: 'app_ru.arb ${e.key}',
      );
    }
  });
}
