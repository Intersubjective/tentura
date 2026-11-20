import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'client DI regeneration resolves the dependencies of PostsCase',
    () async {
      final result = await Process.run('dart', [
        'run',
        'build_runner',
        'build',
        '--build-filter=lib/app/di/di_current.config.dart',
        '--only-check',
        // Invalidate the cached builder result so its diagnostics are emitted.
        '--define=injectable_generator:injectable_config_builder='
            'diagnostic_run=${DateTime.now().microsecondsSinceEpoch}',
      ]);

      final output = '${result.stdout}\n${result.stderr}';
      expect(result.exitCode, 0, reason: output);
      expect(
        output,
        contains('injectable_generator:injectable_config_builder on'),
        reason: 'Injectable must run before its diagnostics can be checked.',
      );
      final unresolvedPostsDependencies = output
          .split('\n')
          .where(
            (line) =>
                line.contains('[PostsCase]') && line.contains('depends on'),
          );
      expect(unresolvedPostsDependencies, isEmpty, reason: output);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
