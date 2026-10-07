import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Post conversion member selection localization', () {
    test(
      'every locale provides a member picker title and carry-over explanation',
      () {
        const keys = [
          'postConvertMembersTitle',
          'postConvertMembersExplanation',
        ];
        final arbs = Directory('l10n')
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.arb'))
            .toList();
        expect(
          arbs.map((file) => file.path),
          containsAll(['l10n/app_en.arb', 'l10n/app_ru.arb']),
        );
        for (final arb in arbs) {
          final values =
              jsonDecode(arb.readAsStringSync()) as Map<String, dynamic>;
          for (final key in keys) {
            expect(
              values[key],
              isA<String>(),
              reason: '${arb.path} must define $key',
            );
            expect(
              (values[key] as String).trim(),
              isNotEmpty,
              reason: '${arb.path}: $key',
            );
          }
          if (arb.path.endsWith('app_en.arb')) {
            expect(
              values['postConvertMembersExplanation'],
              contains('Request'),
              reason:
                  'The member carry-over explanation must use the user-facing term Request',
            );
          }
        }
      },
    );
  });
}
