import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'access explanations have no Post membership translations or references',
    () {
      const prefix = 'requestAccess';
      const retiredKeys = [
        '${prefix}ViaParentPost',
        '${prefix}ViaParentPostUntitled',
        '${prefix}OpenParentPost',
      ];
      final remaining = <String>[];
      for (final locale in ['en', 'ru']) {
        final file = File('l10n/app_$locale.arb');
        final arb = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        for (final key in retiredKeys) {
          for (final entry in [key, '@$key']) {
            if (arb.containsKey(entry)) remaining.add('${file.path}: $entry');
          }
        }
      }

      final references = RegExp('\\b(?:${retiredKeys.join('|')})\\b');
      for (final root in ['lib', 'test']) {
        for (final file in Directory(
          root,
        ).listSync(recursive: true).whereType<File>()) {
          if (!file.path.endsWith('.dart') ||
              const {
                'lib/ui/l10n/l10n.dart',
                'lib/ui/l10n/l10n_en.dart',
                'lib/ui/l10n/l10n_ru.dart',
              }.contains(file.path) ||
              file.path.endsWith('.g.dart') ||
              file.path.endsWith('.freezed.dart')) {
            continue;
          }
          final matches = references.allMatches(file.readAsStringSync());
          for (final match in matches) {
            remaining.add('${file.path}: ${match.group(0)}');
          }
        }
      }
      expect(remaining..sort(), isEmpty);
    },
  );
}
