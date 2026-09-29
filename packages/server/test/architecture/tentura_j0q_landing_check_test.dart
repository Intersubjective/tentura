// tentura-j0q landing gate acceptance (trial merge tentura-acz)

import 'dart:io';

import 'package:test/test.dart';

/// Alloy tentura-j0q landing gate — same paths as bead acceptance harness.
const kJ0qAcceptanceTestPaths = [
  'test/architecture/tentura_j0q_landing_check_test.dart',
  'test/architecture/tentura_j0q_pg_acceptance_probe_test.dart',
];

/// Later landing gates tracked after tentura-j0q (tentura-kd9, fix tentura-ah4
/// enospc selftest); they carry their own markers, not the j0q ones.
const kJ0qTrackedLaterAcceptanceTestPaths = [
  'test/tentura_kd9_enospc_selftest_landing_check_test.dart',
];

const _j0qLandingGateMarker =
    'tentura-j0q landing gate acceptance (trial merge tentura-acz)';

const _trialMergeMarker = 'trial merge tentura-acz';

const _fx7LandingCheckRelative =
    'test/architecture/tentura_fx7_landing_check_test.dart';

const _agentsJ0qLandingComment =
    '<!-- tentura-j0q landing gate acceptance (trial merge tentura-acz) -->';

const _pgAcceptanceProbeRelative =
    'test/architecture/tentura_j0q_pg_acceptance_probe_test.dart';

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
  group('tentura-j0q landing check (trial merge tentura-acz)', () {
    test('j0q acceptance test paths declare j0q landing gate markers', () {
      for (final path in kJ0qAcceptanceTestPaths) {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: 'missing acceptance path $path');
        final source = file.readAsStringSync();
        expect(
          source,
          contains(_j0qLandingGateMarker),
          reason:
              '$path must tag the j0q landing gate for Alloy trial-merge tracking',
        );
        expect(
          source,
          contains(_trialMergeMarker),
          reason: '$path must reference trial merge tentura-acz',
        );
      }
    });

    test(
      'tentura-fx7 landing gate lists j0q acceptance paths for tentura-acz trial merge',
      () {
        final source = _serverTestSource(_fx7LandingCheckRelative);
        for (final path in kJ0qAcceptanceTestPaths) {
          expect(
            source,
            contains("'$path'"),
            reason:
                '$_fx7LandingCheckRelative must include $path so Alloy '
                'tentura-acz landing tracks j0q after tentura-50o (tentura-fx7)',
          );
        }
      },
    );

    test(
      'AGENTS.md records tentura-j0q landing gate acceptance beside prior trial merges',
      () {
        final agents = _repoFile('AGENTS.md').readAsStringSync();
        expect(
          agents,
          contains(_agentsJ0qLandingComment),
          reason:
              'append $_agentsJ0qLandingComment after tentura-u6e on '
              'alloy/tentura-acz trial merge',
        );
      },
    );

    test(
      'bead acceptance: wrapped dart test tentura_j0q_pg_acceptance_probe_test.dart exits 0',
      () {
        final outcome = runJ0qAcceptancePgProbeTest();
        expect(
          outcome.exitCode,
          0,
          reason:
              'tentura-j0q requires '
              '`cd packages/server && '
              '../../scripts/run_with_test_cleanup.sh --timeout 30m -- '
              'dart test $_pgAcceptanceProbeRelative` '
              'to exit 0\n'
              'stdout:\n${outcome.stdout}\n'
              'stderr:\n${outcome.stderr}',
        );
      },
      timeout: const Timeout(Duration(minutes: 31)),
      skip: _skipNestedCleanupInCiDartTest,
    );

    test(
      'bead acceptance: wrapped pg landing command exits 0 (tentura-acz)',
      () {
        final outcome = runJ0qAcceptancePgLanding();
        expect(
          outcome.exitCode,
          0,
          reason:
              'tentura-j0q requires '
              '`cd packages/server && '
              '../../scripts/run_with_test_cleanup.sh --timeout 30m -- '
              'dart test --tags pg --exclude-tags mr` '
              'to exit 0\n'
              'stdout:\n${outcome.stdout}\n'
              'stderr:\n${outcome.stderr}',
        );
      },
      timeout: const Timeout(Duration(minutes: 31)),
      skip: _skipNestedCleanupInCiDartTest,
    );
  });
}

/// Runs the tentura-j0q pg probe test (targeted acz gates before full pg).
({int exitCode, String stdout, String stderr}) runJ0qAcceptancePgProbeTest() {
  final wrapper = _testCleanupWrapper();
  final nestedTmp = Directory.systemTemp.createTempSync(
    'tentura-j0q-probe-nested-',
  );
  try {
    final result = Process.runSync(
      wrapper.path,
      [
        '--timeout',
        '30m',
        '--',
        'dart',
        'test',
        _pgAcceptanceProbeRelative,
      ],
      workingDirectory: _serverPackageRoot().path,
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

/// Runs the exact tentura-acz / tentura-j0q bead pg acceptance command.
({int exitCode, String stdout, String stderr}) runJ0qAcceptancePgLanding() {
  final wrapper = _testCleanupWrapper();
  final nestedTmp = Directory.systemTemp.createTempSync(
    'tentura-j0q-pg-nested-',
  );
  try {
    final result = Process.runSync(
      wrapper.path,
      [
        '--timeout',
        '30m',
        '--',
        'dart',
        'test',
        '--tags',
        'pg',
        '--exclude-tags',
        'mr',
      ],
      workingDirectory: _serverPackageRoot().path,
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

File _testCleanupWrapper() {
  final serverRoot = _serverPackageRoot();
  final candidates = [
    File('${serverRoot.path}/../../scripts/run_with_test_cleanup.sh'),
    File('${serverRoot.parent.parent.path}/scripts/run_with_test_cleanup.sh'),
  ];
  for (final file in candidates) {
    if (file.existsSync()) {
      return file.absolute;
    }
  }
  throw StateError('scripts/run_with_test_cleanup.sh not found');
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

String _serverTestSource(String relativePath) {
  final file = File('${_serverPackageRoot().path}/$relativePath');
  if (!file.existsSync()) {
    throw StateError('server test file not found: ${file.path}');
  }
  return file.readAsStringSync();
}

File _repoFile(String relativePath) {
  for (final prefix in const ['../../', '']) {
    final candidate = File('$prefix$relativePath');
    if (candidate.existsSync()) {
      return candidate.absolute;
    }
  }
  throw StateError('Repo file not found: $relativePath');
}
