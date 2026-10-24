import 'dart:io';

import 'package:crypto/crypto.dart';

/// Directories that hold tool state, not test output, or are not part of the
/// analyzed source tree.
const _ignoredPrefixes = [
  './.dart_tool/',
  './.alloy/',
  './.local/',
  './coverage/',
  './build/native_assets/',
  './build/unit_test_assets/',
];

const _ignoredFiles = ['./custom_lint.log'];

/// Fingerprints every file under the current package (path -> mtime, size and
/// SHA-256 of the bytes), so a suite that rewrites a file with identical
/// content, or edits it while keeping size and mtime, still shows up in
/// [changedPaths].
Map<String, String> snapshotPackageTree() {
  final snapshot = <String, String>{};
  for (final entity in Directory('.').listSync(recursive: true)) {
    if (entity is! File) continue;
    final path = entity.path;
    if (_ignoredPrefixes.any(path.startsWith)) continue;
    if (_ignoredFiles.contains(path)) continue;
    final stat = entity.statSync();
    final digest = sha256.convert(entity.readAsBytesSync());
    snapshot[path] =
        '${stat.modified.microsecondsSinceEpoch}:${stat.size}:$digest';
  }
  return snapshot;
}

/// Paths created, deleted or changed between two snapshots, sorted.
List<String> changedPaths(
  Map<String, String> before,
  Map<String, String> after,
) => {
  ...before.keys.where((p) => before[p] != after[p]),
  ...after.keys.where((p) => before[p] != after[p]),
}.toList()..sort();
