// The scheduler publication-burst load suite runs in the default (non-pg)
// server run, in parallel with the analyzer gates that scan packages/server. A
// report file appearing, being rewritten or flickering under the package
// mid-analysis made the analyzer report a spurious extra issue or crash. Scratch
// output belongs under the system temp directory.

@Tags(['repo-files'])
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

import '../support/package_tree_snapshot.dart';

const _schedulerLoadSuite =
    'test/data/service/constellation_db_scheduler_load_test.dart';
const _schedulerReport = 'constellation_db_scheduler_publication_burst.json';

/// Source trees the analyzer reads, plus the build output directory.
const _watchedRoots = ['lib', 'test', 'bin', 'tool', 'build'];

const _ignoredWatchPrefixes = [
  'build/native_assets/',
  'build/unit_test_assets/',
];

/// Matches `File('build/...')` / `Directory("build/...")` style constructions.
final _packageRelativeBuildPath = RegExp(
  r'''(File|Directory)\(\s*['"]build/''',
);

bool _isPgSuite(File file) {
  if (file.path.endsWith('_pg_test.dart')) return true;
  final header = file.readAsStringSync().split('library;').first;
  return RegExp(r'@Tags\(\[[^\]]*\bpg\b').hasMatch(header);
}

void main() {
  group('Scheduler publication-burst load suite', () {
    test(
      'writes its report under the system temp directory and nowhere in '
      'packages/server, not even transiently',
      () async {
        final scratch = Directory.systemTemp.createTempSync(
          'scheduler_report_',
        );
        addTearDown(() => scratch.deleteSync(recursive: true));

        final before = snapshotPackageTree();
        final touched = <String>{};
        final watchers = <StreamSubscription<FileSystemEvent>>[];
        for (final root in _watchedRoots) {
          final dir = Directory(root);
          if (!dir.existsSync()) continue;
          watchers.add(
            dir.watch(recursive: true).listen((event) {
              if (event.isDirectory) return;
              final path = event.path.replaceFirst(
                '${Directory.current.path}/',
                '',
              );
              if (_ignoredWatchPrefixes.any(path.startsWith)) return;
              touched.add('${event.type}:$path');
            }),
          );
        }
        addTearDown(() async {
          for (final watcher in watchers) {
            await watcher.cancel();
          }
        });

        final result = await Process.run(
          Platform.resolvedExecutable,
          ['test', _schedulerLoadSuite, '-j', '1'],
          environment: {'TMPDIR': scratch.path},
        );
        await Future<void>.delayed(const Duration(seconds: 1));
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );

        final reports = scratch
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.uri.pathSegments.last == _schedulerReport);
        expect(
          reports,
          isNotEmpty,
          reason:
              '$_schedulerLoadSuite must write $_schedulerReport under '
              'Directory.systemTemp',
        );
        expect(
          touched.toList()..sort(),
          isEmpty,
          reason:
              'files were created, changed or removed in the package while '
              'the suite ran',
        );
        expect(changedPaths(before, snapshotPackageTree()), isEmpty);
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });

  group('Default-run suites', () {
    test(
      'do not build File or Directory paths under the package build/ dir',
      () {
        final offenders = [
          for (final file
              in Directory('test')
                  .listSync(recursive: true)
                  .whereType<File>()
                  .where((f) => f.path.endsWith('.dart')))
            if (!_isPgSuite(file) &&
                !file.path.startsWith('test/perf/') &&
                !file.path.endsWith(
                  'non_pg_suites_leave_server_package_untouched_test.dart',
                ) &&
                _packageRelativeBuildPath.hasMatch(file.readAsStringSync()))
              file.path,
        ]..sort();

        expect(
          offenders,
          isEmpty,
          reason:
              'a suite in the default (non-pg) run writes report output into '
              'packages/server/build; use Directory.systemTemp instead',
        );
      },
    );
  });
}
