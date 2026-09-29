import 'dart:io';

import 'package:test/test.dart';

/// P0.2 acceptance: postgres-tentura v0.8.1 pins and `mr_sync` before epoch bump.
void main() {
  group('P0.2 postgres-tentura image pins', () {
    final repoRoot = _repoRoot();

    for (final relativePath in const [
      'compose.dev.yaml',
      'compose.prod.yaml',
      '.github/workflows/pipeline.yml',
    ]) {
      test('$relativePath references postgres-tentura:v0.8.1', () {
        final source = _readRepoFile(repoRoot, relativePath);
        expect(
          source,
          contains('vbulavintsev/postgres-tentura:v0.8.1'),
          reason: 'P0.2 bumps pgmer2 to 0.8.1 in compose and CI',
        );
        expect(
          source,
          isNot(contains('vbulavintsev/postgres-tentura:v0.8.0')),
          reason: 'v0.8.0 must not remain after P0.2',
        );
      });
    }
  });

  group('P0.2 WitnessWindowRepository.bumpMrEpoch', () {
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

  group('P0.2 mr_bump_publish_epoch SQL migration', () {
    test('replaces mr_bump_publish_epoch to PERFORM mr_sync before bump', () {
      final bodies = _readMigrationBodiesAfterBaseline(_repoRoot());
      expect(
        bodies,
        contains(RegExp(
          r'CREATE\s+(OR\s+REPLACE\s+)?FUNCTION\s+public\.mr_bump_publish_epoch',
          multiLine: true,
        )),
        reason: 'post-baseline migration must replace mr_bump_publish_epoch',
      );
      final replacement = RegExp(
        r'CREATE\s+(OR\s+REPLACE\s+)?FUNCTION\s+public\.mr_bump_publish_epoch'
        r'[\s\S]*?\$\$[\s\S]*?\$\$',
        multiLine: true,
      ).firstMatch(bodies);
      expect(replacement, isNotNull);
      final block = replacement!.group(0)!;
      expect(
        block,
        contains('mr_sync'),
        reason: 'mr_bump_publish_epoch must call mr_sync before epoch bump',
      );
      final syncIndex = block.indexOf('mr_sync');
      final bumpIndex = block.indexOf('mr_publish_epoch');
      expect(syncIndex, lessThan(bumpIndex));
    });
  });
}

Directory _repoRoot() {
  for (final start in [
    Directory.current,
    Directory('../../'),
    Directory('../../../'),
  ]) {
    final script = File('${start.path}/scripts/run_with_test_cleanup.sh');
    if (script.existsSync()) {
      return start.absolute;
    }
  }
  throw StateError('repo root not found');
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

String _readRepoFile(Directory repoRoot, String relativePath) {
  final file = File('${repoRoot.path}/$relativePath');
  if (!file.existsSync()) {
    throw StateError('repo file not found: ${file.path}');
  }
  return file.readAsStringSync();
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

String _readMigrationBodiesAfterBaseline(Directory repoRoot) {
  final migrationDir = repoRoot.uri.resolve(
    'packages/server/lib/data/database/migration/',
  );
  final buffer = StringBuffer();
  final registry = File.fromUri(
    migrationDir.resolve('_migrations.dart'),
  ).readAsStringSync();
  for (final match in RegExp(r"part '(m\d+\.dart)'").allMatches(registry)) {
    final name = match.group(1)!;
    final version = int.parse(name.substring(1, 5));
    if (version > 193) {
      buffer.write(File.fromUri(migrationDir.resolve(name)).readAsStringSync());
    }
  }
  return buffer.toString();
}
