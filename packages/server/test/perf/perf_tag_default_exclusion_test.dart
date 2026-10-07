import 'dart:io';

import 'package:test/test.dart';

/// The perf harness runs real timings against a shared MeritRank service, so it
/// must never ride along in the default server run (`--exclude-tags pg`) or the
/// plain pg run (`--tags pg --exclude-tags mr`). This guard is untagged so the
/// default run is where a regression is noticed.
void main() {
  final perfDir = Directory('test/perf');
  final perfSuites = perfDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('_test.dart'))
      .where((f) => _declaredTags(f).contains('perf'))
      .toList();

  test('dart_test.yaml declares the perf tag', () {
    final config = File('dart_test.yaml').readAsStringSync();

    expect(config, matches(RegExp('^  perf:', multiLine: true)));
  });

  test('the perf directory holds at least one perf-tagged suite', () {
    expect(perfSuites, isNotEmpty);
  });

  for (final file in perfSuites) {
    final name = file.uri.pathSegments.last;

    test('$name is tagged perf, pg and mr so default and pg runs skip it', () {
      expect(_declaredTags(file), containsAll(<String>['perf', 'pg', 'mr']));
    });
  }

  group('the perf-tagged suites', () {
    final paths = perfSuites.map((f) => f.path).toList();

    Future<ProcessResult> dartTest(List<String> selectors) => Process.run(
      Platform.resolvedExecutable,
      ['test', ...selectors, ...paths],
    );

    // 79 is `dart test`'s "no tests were run" status.
    test('run nothing in the default server run (--exclude-tags pg)', () async {
      final result = await dartTest(['--exclude-tags', 'pg']);

      expect(result.exitCode, 79, reason: '${result.stdout}${result.stderr}');
    });

    test('run nothing in the plain pg run (--tags pg --exclude-tags mr)', () async {
      final result = await dartTest(['--tags', 'pg', '--exclude-tags', 'mr']);

      expect(result.exitCode, 79, reason: '${result.stdout}${result.stderr}');
    });
  });
}

Set<String> _declaredTags(File file) {
  final header = file.readAsStringSync().split('library;').first;
  final tags = RegExp(r'@Tags\(\[([^\]]*)\]\)').firstMatch(header);
  if (tags == null) return {};
  return tags
      .group(1)!
      .split(',')
      .map((t) => t.trim().replaceAll("'", ''))
      .where((t) => t.isNotEmpty)
      .toSet();
}
