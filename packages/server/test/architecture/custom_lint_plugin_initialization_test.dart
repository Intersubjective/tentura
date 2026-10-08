import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('Custom lint gate plugin initialization', () {
    for (final package in ['packages/client', 'packages/server']) {
      test(
        '$package rejects failed setup and excess violations '
        'while accepting healthy zero-count runs',
        () async {
          final repoRoot = Directory('../..').absolute;
          final result = await Process.run(
            'bash',
            [
              '${repoRoot.path}/scripts/'
                  'test_check_custom_lints_plugin_initialization.sh',
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
