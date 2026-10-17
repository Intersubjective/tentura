@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Constellation domain describes Beacon nodes with its own pure records
/// (`LayoutNodeSpec`); the graph feature's scene entity `NodeDetails` is a UI
/// concern that only the scene side maps to.
void main() {
  // Works from the repo root and from `packages/client`.
  final packageRoot =
      File('pubspec.yaml').existsSync() &&
          Directory('lib/features').existsSync()
      ? ''
      : 'packages/client/';

  test('constellation domain does not import the graph NodeDetails entity', () {
    final sourceFiles = Directory('${packageRoot}lib/features/constellation/domain')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => !file.path.endsWith('.freezed.dart'));

    expect(sourceFiles, isNotEmpty);
    for (final file in sourceFiles) {
      expect(
        file.readAsStringSync(),
        isNot(contains('graph/domain/entity/node_details.dart')),
        reason: '${file.path} must not import graph node_details.dart',
      );
    }
  });
}
