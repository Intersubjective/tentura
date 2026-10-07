import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('constellation presentation composition ownership', () {
    test('constellation read use cases never compose presentation', () {
      final composers = Directory('lib/features/constellation/domain/use_case')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .where(
            (file) => file.readAsStringSync().contains(
              'composeConstellationPresentation',
            ),
          )
          .map((file) => file.path)
          .toList();
      expect(
        composers,
        isEmpty,
        reason: 'Renaming the old case cannot retain read-side composition',
      );
    });

    test('UI composition calls use the injected presentation composer', () {
      final directCall = RegExp(r'\bcomposeConstellationPresentation\s*\(');
      final bypasses = Directory('lib/features/constellation/ui')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .where((file) => directCall.hasMatch(file.readAsStringSync()))
          .map((file) => file.path)
          .toList();
      expect(
        bypasses,
        isEmpty,
        reason:
            'All composition must pass through the injectable callback so the counter observes every call',
      );
    });
  });
}
