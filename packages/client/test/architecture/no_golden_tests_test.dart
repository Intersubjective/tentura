import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Golden tests are banned project-wide; see `.cursor/rules/no-golden-tests.mdc`.
void main() {
  test('no golden tests or baselines under test/', () {
    final root = Directory('test').existsSync()
        ? Directory('test')
        : Directory('packages/client/test');
    final offenders = <String>[];
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File) continue;
      final path = entity.path;
      if (path.endsWith('no_golden_tests_test.dart')) continue;
      if (path.contains('/goldens/')) {
        offenders.add(path);
      } else if (path.endsWith('.dart') &&
          RegExp('matchesGoldenFile|matchesReferenceImage')
              .hasMatch(entity.readAsStringSync())) {
        offenders.add(path);
      }
    }
    expect(offenders, isEmpty, reason: 'golden tests are disabled');
  });
}
