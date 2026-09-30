// tentura-fx7 landing gate acceptance (trial merge tentura-50o)

import 'dart:io';

import 'package:test/test.dart';

import '../support/server_ci_lint_gate_harness.dart';

/// Alloy tentura-fx7 landing gate — same paths as bead acceptance harness.
const kFx7AcceptanceTestPaths = [
  'test/architecture/tentura_fx7_landing_check_test.dart',
  'test/architecture/tentura_fx7_pg_acceptance_probe_test.dart',
];

/// Later landing gates tracked after tentura-fx7 (tentura-j0q, trial merge
/// tentura-acz); they carry their own markers, not the fx7 ones.
const kFx7TrackedLaterAcceptanceTestPaths = [
  'test/architecture/tentura_j0q_landing_check_test.dart',
  'test/architecture/tentura_j0q_pg_acceptance_probe_test.dart',
];

const _fx7LandingGateMarker =
    'tentura-fx7 landing gate acceptance (trial merge tentura-50o)';

const _trialMergeMarker = 'trial merge tentura-50o';

const _2noLandingCheckRelative =
    'test/architecture/tentura_2no_landing_check_test.dart';

const _agentsFx7LandingComment =
    '<!-- tentura-fx7 landing gate acceptance (trial merge tentura-50o) -->';

const _pgAcceptanceProbeRelative =
    'test/architecture/tentura_fx7_pg_acceptance_probe_test.dart';

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
  group('tentura-fx7 landing check (trial merge tentura-50o)', () {
    test('fx7 acceptance test paths declare fx7 landing gate markers', () {
      for (final path in kFx7AcceptanceTestPaths) {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: 'missing acceptance path $path');
        final source = file.readAsStringSync();
        expect(
          source,
          contains(_fx7LandingGateMarker),
          reason:
              '$path must tag the fx7 landing gate for Alloy trial-merge tracking',
        );
        expect(
          source,
          contains(_trialMergeMarker),
          reason: '$path must reference trial merge tentura-50o',
        );
      }
    });

    test(
      'tentura-2no landing gate lists fx7 acceptance paths for tentura-50o trial merge',
      () {
        final source = _serverTestSource(_2noLandingCheckRelative);
        for (final path in kFx7AcceptanceTestPaths) {
          expect(
            source,
            contains("'$path'"),
            reason:
                '$_2noLandingCheckRelative k2noAcceptanceTestPaths must include '
                '$path so Alloy tentura-50o landing tracks fx7 (tentura-fx7)',
          );
        }
      },
    );

    test(
      'AGENTS.md records tentura-fx7 landing gate acceptance beside prior trial merges',
      () {
        final agents = _repoFile('AGENTS.md').readAsStringSync();
        expect(
          agents,
          contains(_agentsFx7LandingComment),
          reason:
              'append $_agentsFx7LandingComment after tentura-olc on '
              'alloy/tentura-50o trial merge',
        );
      },
    );

    test(
      'bead acceptance: wrapped dart test tentura_fx7_pg_acceptance_probe_test.dart exits 0',
      () {
        final outcome = runFx7AcceptancePgProbeTest();
        expect(
          outcome.exitCode,
          0,
          reason:
              'tentura-fx7 requires '
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
      'bead acceptance: wrapped pg landing command exits 0 (tentura-50o)',
      () {
        final outcome = runFx7AcceptancePgLanding();
        expect(
          outcome.exitCode,
          0,
          reason:
              'tentura-fx7 requires '
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

/// Runs the tentura-fx7 pg probe test (static remediation gates before full pg).
({int exitCode, String stdout, String stderr}) runFx7AcceptancePgProbeTest() {
  final wrapper = _testCleanupWrapper();
  final nestedTmp = Directory.systemTemp.createTempSync(
    'tentura-fx7-probe-nested-',
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
