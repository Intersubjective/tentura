import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Constellation domain stays free of Flutter widgets and the vendored graph
/// package. Layout uses pure Dart geometry (`dart:ui` `Offset`/`Size` only).
///
/// Enforced by
/// `docs/plans/force-directed-graphview-scene-decoupling-plan.md` (A9, M08).
void main() {
  test('constellation domain does not import Flutter or force_directed_graphview',
      () {
    final domainDir = Directory('lib/features/constellation/domain');
    final sourceFiles = domainDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => !file.path.endsWith('.freezed.dart'));

    for (final file in sourceFiles) {
      final source = file.readAsStringSync();
      expect(
        source,
        isNot(contains('package:flutter/')),
        reason: '${file.path} must not import package:flutter',
      );
      expect(
        source,
        isNot(contains('package:force_directed_graphview')),
        reason: '${file.path} must not import force_directed_graphview',
      );
    }
  });
}
