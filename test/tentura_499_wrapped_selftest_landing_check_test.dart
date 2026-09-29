import 'dart:io';

import 'package:test/test.dart';

// tentura-499 landing gate acceptance (fix tentura-5zq wrapped selftest)

/// Alloy tentura-499 — same path as bead acceptance harness.
const k499AcceptanceTestPaths = [
  'test/tentura_499_wrapped_selftest_landing_check_test.dart',
];

const _499LandingGateMarker =
    'tentura-499 landing gate acceptance (fix tentura-5zq wrapped selftest)';

const _parentLandingMarker = 'fix tentura-5zq';

const _5zqGateTestPath =
    'packages/server/test/architecture/tentura_5zq_server_ci_analyze_gate_test.dart';

Object get _skipNestedCleanupInCiDartTest {
  final env = Platform.environment;
  if (env['GITHUB_ACTIONS'] == 'true' ||
      env['CI'] == 'true' ||
      env['TEST_TARGET'] == 'server' ||
      env['TENTURA_U6E_NESTED_SUITE'] == 'true') {
    return 'do not nest run_with_test_cleanup.sh inside CI dart test';
  }
  return false;
}

void main() {
  group('tentura-499 wrapped selftest landing check (fix tentura-5zq)', () {
    test('499 acceptance test paths declare tentura-499 landing gate markers', () {
      for (final path in k499AcceptanceTestPaths) {
        final file = _repoFile(path);
        expect(file.existsSync(), isTrue, reason: 'missing acceptance path $path');
        final source = file.readAsStringSync();
        expect(
          source,
          contains(_499LandingGateMarker),
          reason:
              '$path must tag the 499 landing gate for Alloy trial-merge tracking',
        );
        expect(
          source,
          contains(_parentLandingMarker),
          reason: '$path must reference parent landing bead tentura-5zq',
        );
      }
    });

    test(
      'tentura-5zq acceptance paths include tentura-499 wrapped selftest gate',
      () {
        final gate = _repoFile(_5zqGateTestPath);
        expect(gate.existsSync(), isTrue, reason: 'missing $_5zqGateTestPath');
        final source = gate.readAsStringSync();
        for (final path in k499AcceptanceTestPaths) {
          expect(
            source.contains("'$path'"),
            isTrue,
            reason:
                'k5zqAcceptanceTestPaths must list $path after tentura-499 lands',
          );
        }
      },
    );

    test(
      'bead acceptance: nested wrapped selftest exits 0 (tentura-499)',
      () {
        final outcome = runTentura499BeadAcceptance();
        expect(
          outcome.exitCode,
          0,
          reason:
              'tentura-499 requires '
              '`cd <repo> && '
              './scripts/run_with_test_cleanup.sh --timeout 10m -- '
              'bash scripts/run_with_test_cleanup_selftest.sh` '
              'to exit 0 on alloy/tentura-5zq\n'
              'stdout:\n${outcome.stdout}\n'
              'stderr:\n${outcome.stderr}',
        );
        expect(
          outcome.combined,
          contains('passed=16 failed=0'),
          reason:
              'wrapped selftest must finish with zero failures when Alloy '
              'runs the acceptance command inside an outer wrapper\n'
              'combined output:\n${outcome.combined}',
        );
      },
      timeout: const Timeout(Duration(minutes: 12)),
      skip: _skipNestedCleanupInCiDartTest,
    );
  });
}

/// Runs tentura-499 acceptance the way Alloy does: an outer wrapped harness
/// invokes the bead command as the inner wrapped command.
({int exitCode, String stdout, String stderr, String combined})
runTentura499BeadAcceptance() {
  final wrapper = _testCleanupWrapper();
  final repo = _repoRoot();
  final nestedTmp = Directory.systemTemp.createTempSync('tentura-499-nested-');
  try {
    final result = Process.runSync(
      wrapper.path,
      [
        '--timeout',
        '10m',
        '--',
        wrapper.path,
        '--timeout',
        '10m',
        '--',
        'bash',
        'scripts/run_with_test_cleanup_selftest.sh',
      ],
      workingDirectory: repo.path,
      environment: {
        ...Platform.environment,
        'DART_SUPPRESS_ANALYTICS': 'true',
        'TMPDIR': nestedTmp.path,
      },
    );
    final stdout = result.stdout as String;
    final stderr = result.stderr as String;
    return (
      exitCode: result.exitCode,
      stdout: stdout,
      stderr: stderr,
      combined: '$stdout$stderr',
    );
  } finally {
    nestedTmp.deleteSync(recursive: true);
  }
}

Directory _repoRoot() {
  for (final start in [
    Directory.current,
    Directory('..'),
    Directory('../..'),
  ]) {
    final script = File('${start.path}/scripts/run_with_test_cleanup.sh');
    if (script.existsSync()) {
      return start.absolute;
    }
  }
  throw StateError('repo root not found');
}

File _repoFile(String relativePath) {
  return File('${_repoRoot().path}/$relativePath');
}

File _testCleanupWrapper() {
  final file = File('${_repoRoot().path}/scripts/run_with_test_cleanup.sh');
  if (!file.existsSync()) {
    throw StateError('scripts/run_with_test_cleanup.sh not found');
  }
  return file.absolute;
}
