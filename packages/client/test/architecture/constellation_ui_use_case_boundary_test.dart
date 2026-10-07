import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Constellation UI use case boundary', () {
    final packageRoot = Directory('lib/features').existsSync()
        ? ''
        : 'packages/client/';

    for (final dependency in [
      'ForwardRepository',
      'ConstellationMemberWebsPort',
    ]) {
      test('UI delegates through cases instead of $dependency', () {
        final files = Directory('${packageRoot}lib/features/constellation/ui')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))
            .toList();
        expect(files, isNotEmpty);

        final violations = <String>[];
        for (final file in files) {
          final lines = file.readAsLinesSync();
          for (var index = 0; index < lines.length; index++) {
            if (lines[index].contains(dependency)) {
              violations.add(
                '${file.path}:${index + 1}: ${lines[index].trim()}',
              );
            }
          }
        }

        expect(
          violations,
          isEmpty,
          reason:
              'Constellation UI must access $dependency through a use case.',
        );
      });
    }
  });
}
