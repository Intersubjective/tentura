@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('Analyzer baseline gate plugin initialization', () {
    for (final package in ['packages/client', 'packages/server']) {
      test(
        '$package rejects failed setup and excess issues '
        'while accepting healthy clean runs',
        () async {
          final repoRoot = Directory('../..').absolute;
          final result = await Process.run(
            'bash',
            [
              '${repoRoot.path}/scripts/'
                  'test_check_analyze_baseline_plugin_initialization.sh',
              package,
            ],
            workingDirectory: repoRoot.path,
          );
          expect(
            result.exitCode,
            0,
            reason: '${result.stdout}\n${result.stderr}',
          );
        },
        timeout: const Timeout(Duration(seconds: 30)),
      );
    }
  });
}
