@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('beacon_threads and shared UI do not import beacon_view', () {
    final roots = [
      'lib/features/beacon_threads',
      'lib/ui',
    ];

    for (final root in roots) {
      test('$root has no package:tentura/features/beacon_view/ imports', () {
        final dir = Directory(root);
        expect(dir.existsSync(), isTrue, reason: root);

        final violations = <String>[];
        for (final file
            in dir
                .listSync(recursive: true)
                .whereType<File>()
                .where((f) => f.path.endsWith('.dart'))) {
          final lines = file.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            final line = lines[i];
            if (line.contains('package:tentura/features/beacon_view/')) {
              violations.add('${file.path}:${i + 1}: ${line.trim()}');
            }
          }
        }

        expect(
          violations,
          isEmpty,
          reason: '$root must not depend on beacon_view internals.',
        );
      });
    }
  });
}
