@Tags(['repo-files'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Include all package sources/tests (integration_test, test_driver and tool
// included), plus the workspace's root test tree. Ignore generated build
// directories, not source-file extensions or only Dart imports.
Iterable<File> _sourceFiles(Directory root) sync* {
  if (!root.existsSync()) return;
  for (final entry in root.listSync(followLinks: false)) {
    if (entry is File) {
      yield entry;
    } else if (entry is Directory &&
        !{'.dart_tool', 'build', '.git', 'node_modules', 'reports'}.contains(
          entry.path.split('/').last,
        )) {
      yield* _sourceFiles(entry);
    }
  }
}

void main() {
  test(
    'Post composer has no obsolete local draft store or callers in package or workspace tests',
    () {
      // Split the obsolete basename so this guard does not match itself.
      final basename = ['post_create_composer', 'draft_store'].join('_');
      final storeFiles = <String>[];
      final callers = <String>[];
      final roots = [
        Directory(
          'lib',
        ), // packages/client/lib, even with any other scan roots.
        Directory('test'), // packages/client/test.
        Directory('../../test'), // Workspace root test tree.
        Directory.current, // Other package sources and browser test trees.
      ];
      final scanned = <String>{};
      for (final root in roots) {
        for (final file in _sourceFiles(root)) {
          if (!scanned.add(file.absolute.path)) continue;
          if (file.path.split('/').last.startsWith(basename)) {
            storeFiles.add(file.path);
          }
          final String text;
          try {
            text = utf8.decode(file.readAsBytesSync());
          } on FormatException {
            // Fonts, images and other binary assets cannot contain imports.
            continue;
          }
          if (text.contains(basename)) callers.add(file.path);
        }
      }
      expect(
        {'storeFiles': storeFiles, 'callers': callers},
        {'storeFiles': isEmpty, 'callers': isEmpty},
        reason: 'the server is the sole source for reopening a Post draft',
      );
    },
  );
}
