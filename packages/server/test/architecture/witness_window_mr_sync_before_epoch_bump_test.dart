import 'dart:io';

import 'package:test/test.dart';

/// `bumpMrEpoch` must flush MeritRank (`mr_sync`) before bumping the epoch.
void main() {
  group('WitnessWindowRepository.bumpMrEpoch', () {
    test('runs mr_sync before bumping mr_publish_epoch', () {
      final source = _readServerFile(
        'lib/data/repository/witness_window_repository.dart',
      );
      final bumpBlock = _extractBumpMrEpochBlock(source);
      expect(
        bumpBlock,
        contains('mr_sync'),
        reason: 'bumpMrEpoch must SELECT mr_sync() before epoch increment',
      );
      final syncIndex = bumpBlock.indexOf('mr_sync');
      final epochBumpIndex = bumpBlock.indexOf('mr_publish_epoch');
      expect(syncIndex, greaterThan(-1));
      expect(epochBumpIndex, greaterThan(-1));
      expect(
        syncIndex,
        lessThan(epochBumpIndex),
        reason: 'mr_sync must precede the publish-epoch update in bumpMrEpoch',
      );
    });
  });
}

Directory _serverPackageRoot() {
  for (final path in const ['.', '../../packages/server']) {
    final dir = Directory(path);
    final candidate = File('${dir.path}/lib/env.dart');
    if (candidate.existsSync()) {
      return dir.absolute;
    }
  }
  throw StateError('server package root not found');
}

String _readServerFile(String relativePath) {
  final file = File('${_serverPackageRoot().path}/$relativePath');
  if (!file.existsSync()) {
    throw StateError('server file not found: ${file.path}');
  }
  return file.readAsStringSync();
}

String _extractBumpMrEpochBlock(String source) {
  final start = source.indexOf('Future<void> bumpMrEpoch()');
  expect(start, greaterThan(-1), reason: 'bumpMrEpoch must exist');
  final end = source.indexOf('Future<int> gcStaleWindows()', start);
  expect(end, greaterThan(start));
  return source.substring(start, end);
}
