import 'dart:io';

import 'server_ci_lint_gate_harness.dart';

const kForwardBandWitnessAdmissionIntegrationPgTestRelPath =
    'test/domain/use_case/forward_band_witness_admission_integration_pg_test.dart';

/// Runs the real G3a integration pg/mr file (setUp exercises shared cleanup).
({int exitCode, String stdout, String stderr})
runForwardBandWitnessAdmissionIntegrationPgTestOnHostTree() {
  final nestedTmp = Directory.systemTemp.createTempSync('tentura-6koo-g3a-');
  try {
    final result = Process.runSync(
      testCleanupWrapperFromServerPackage().path,
      [
        '--timeout',
        '15m',
        '--',
        'dart',
        'test',
        kForwardBandWitnessAdmissionIntegrationPgTestRelPath,
        '--tags',
        'mr',
        '-j',
        '1',
      ],
      workingDirectory: serverPackageRoot().path,
      environment: {
        ...Platform.environment,
        'DART_SUPPRESS_ANALYTICS': 'true',
        'TMPDIR': nestedTmp.path,
      },
    );
    return (
      exitCode: result.exitCode,
      stdout: result.stdout as String,
      stderr: result.stderr as String,
    );
  } finally {
    nestedTmp.deleteSync(recursive: true);
  }
}
