import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'ConstellationCubit passes dart analyze without warnings',
    () async {
      const sourcePath =
          'lib/features/constellation/ui/bloc/constellation_cubit.dart';
      // Keep this diagnostic check independent of telemetry network access.
      final result = await Process.run('dart', [
        '--suppress-analytics',
        'analyze',
        sourcePath,
      ]);

      expect(
        result.exitCode,
        0,
        reason: 'dart analyze $sourcePath\n'
            '${result.stdout}\n${result.stderr}',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
