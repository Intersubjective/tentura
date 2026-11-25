@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:test/test.dart';

// The CI selector scans for quoted tag literals, including in test bodies.
const _multiConnection =
    'multi'
    '-connection';

void main() {
  test(
    'CI selects the private-person merge and tag suites for multiple connections',
    () async {
      final selected = await _multiConnectionSuites();
      const suites = [
        'test/domain/use_case/phantom_merge_case_pg_test.dart',
        'test/domain/use_case/phantom_merge_worker_pg_test.dart',
        'test/data/repository/people_tags_phantom_membership_pg_test.dart',
      ];
      expect(
        suites.where((suite) {
          final header = File(suite).readAsStringSync().split('library;').first;
          return !selected.contains(suite) ||
              !RegExp(
                r'''@Tags\s*\(\s*\[\s*['"]pg['"]\s*,\s*['"]multi-connection['"]\s*,?\s*\]\s*\)''',
              ).hasMatch(header);
        }),
        isEmpty,
        reason:
            'Each suite needs the library tag used by the multi-connection CI job.',
      );
    },
  );
}

Future<Set<String>> _multiConnectionSuites() async {
  final result = await Process.run(
    'python3',
    [
      '../../scripts/ci_select_tests.py',
      'test',
      '--tag',
      _multiConnection,
    ],
  );
  expect(result.exitCode, 0, reason: result.stderr.toString());
  return (result.stdout as String).trim().split('\n').toSet();
}
