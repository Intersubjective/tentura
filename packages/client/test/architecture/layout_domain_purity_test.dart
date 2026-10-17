@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Layout domain code is pure Dart: geometry travels as domain records
/// (`layout_geometry.dart`), never as `dart:ui` `Offset`/`Size`.
void main() {
  // Works from the repo root and from `packages/client`.
  final packageRoot =
      File('pubspec.yaml').existsSync() &&
          Directory('lib/features').existsSync()
      ? ''
      : 'packages/client/';
  final layoutDomainDirs = [
    '${packageRoot}lib/features/constellation/domain',
    '${packageRoot}lib/features/graph/domain/layout',
  ];

  for (final dir in layoutDomainDirs) {
    test('$dir imports neither dart:ui nor package:flutter', () {
      final sourceFiles = Directory(dir)
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .where((file) => !file.path.endsWith('.freezed.dart'));

      expect(sourceFiles, isNotEmpty);
      for (final file in sourceFiles) {
        final source = file.readAsStringSync();
        expect(
          source,
          isNot(contains('dart:ui')),
          reason: '${file.path} must not import dart:ui',
        );
        expect(
          source,
          isNot(contains('package:flutter')),
          reason: '${file.path} must not import package:flutter',
        );
      }
    });
  }
}
