// tentura-pl4 landing gate acceptance (fix tentura-8u7)

import 'dart:io';

import 'package:test/test.dart';

import '../support/server_ci_lint_gate_harness.dart';

/// Alloy tentura-pl4 landing gate — same paths as bead acceptance harness.
const kPl4AcceptanceTestPaths = [
  'test/architecture/tentura_pl4_landing_check_test.dart',
  'test/architecture/tentura_pl4_di_acceptance_probe_test.dart',
];

/// Later landing gates tracked after tentura-pl4 (tentura-30e nesting
/// remediation); they carry their own markers, not the pl4 ones.
const kPl4TrackedLaterAcceptanceTestPaths = [
  'test/architecture/tentura_30e_landing_check_nesting_test.dart',
  'test/architecture/tentura_3w2_landing_check_test.dart',
];

const _pl4LandingGateMarker =
    'tentura-pl4 landing gate acceptance (fix tentura-8u7)';

const _parentLandingMarker = 'fix tentura-8u7';

const _8u7LandingCheckRelative =
    'test/architecture/tentura_8u7_landing_check_test.dart';

const _8u7LandingGateMarker =
    'tentura-8u7 landing gate acceptance (parent tentura-8u7)';

const _j0qLandingCheckRelative =
    'test/architecture/tentura_j0q_landing_check_test.dart';

const _agentsPl4LandingComment =
    '<!-- tentura-pl4 landing gate acceptance (fix tentura-8u7) -->';

const _harnessPl4RunnerName = 'runPl4AcceptanceNonPgDartTest';

const _8u7TrialMergeRef = 'alloy/tentura-8u7';

Object get _skipNestedCleanupInCiDartTest {
  final env = Platform.environment;
  if (env['GITHUB_ACTIONS'] == 'true' ||
      env['CI'] == 'true' ||
      env['TEST_TARGET'] == 'server' ||
      env['TENTURA_U6E_NESTED_SUITE'] == 'true') {
    return 'do not recursively nest run_with_test_cleanup.sh';
  }
  return false;
}

void main() {
  group('tentura-pl4 landing check (fix tentura-8u7)', () {
    test('pl4 acceptance test paths declare pl4 landing gate markers', () {
      for (final path in kPl4AcceptanceTestPaths) {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: 'missing acceptance path $path');
        final source = file.readAsStringSync();
        expect(
          source,
          contains(_pl4LandingGateMarker),
          reason:
              '$path must tag the pl4 landing gate for Alloy trial-merge tracking',
        );
        expect(
          source,
          contains(_parentLandingMarker),
          reason: '$path must reference parent landing bead tentura-8u7',
        );
      }
    });

    test(
      'tentura-8u7 parent landing gate lists pl4 acceptance paths',
      () {
        final file = File('${serverPackageRoot().path}/$_8u7LandingCheckRelative');
        expect(
          file.existsSync(),
          isTrue,
          reason:
              'missing $_8u7LandingCheckRelative — parent tentura-8u7 gate',
        );
        final source = file.readAsStringSync();
        expect(
          source,
          contains(_8u7LandingGateMarker),
          reason: 'parent gate must carry the tentura-8u7 landing marker',
        );
        for (final path in kPl4AcceptanceTestPaths) {
          expect(
            source,
            contains("'$path'"),
            reason:
                '$_8u7LandingCheckRelative k8u7AcceptanceTestPaths must list '
                '$path so Alloy tentura-8u7 landing tracks pl4 (tentura-pl4)',
          );
        }
      },
    );

    test(
      'tentura-j0q landing gate lists pl4 acceptance paths after tentura-8u7',
      () {
        final source = File(
          '${serverPackageRoot().path}/$_j0qLandingCheckRelative',
        ).readAsStringSync();
        for (final path in kPl4AcceptanceTestPaths) {
          expect(
            source,
            contains("'$path'"),
            reason:
                'kJ0qTrackedLaterAcceptanceTestPaths must list $path after '
                'tentura-pl4 lands on $_8u7TrialMergeRef',
          );
        }
      },
    );

    test(
      'server CI harness exposes pl4 non-pg bead acceptance runner',
      () {
        final harness = readCheckCustomLintsScriptFromRepo();
        // Harness lives beside the lint gate helpers in server_ci_lint_gate_harness.dart.
        final gateHarness = File(
          '${serverPackageRoot().path}/test/support/server_ci_lint_gate_harness.dart',
        ).readAsStringSync();
        expect(
          gateHarness,
          contains(_harnessPl4RunnerName),
          reason:
              'server_ci_lint_gate_harness must define $_harnessPl4RunnerName '
              'for tentura-pl4 non-pg landing acceptance',
        );
        expect(
          harness,
          isNotEmpty,
          reason: 'lint gate harness must remain readable from server package',
        );
      },
    );

    test(
      'bead acceptance: wrapped dart test --exclude-tags pg exits 0 (tentura-8u7 landing)',
      () {
        final gateHarness = File(
          '${serverPackageRoot().path}/test/support/server_ci_lint_gate_harness.dart',
        ).readAsStringSync();
        expect(
          gateHarness,
          contains(_harnessPl4RunnerName),
          reason: 'pl4 landing runner must exist before nested acceptance',
        );
        final outcome = runPl4AcceptanceNonPgDartTest();
        expect(
          outcome.exitCode,
          0,
          reason:
              'tentura-pl4 requires '
              '`cd packages/server && '
              '../../scripts/run_with_test_cleanup.sh --timeout 30m -- '
              'dart test --exclude-tags pg` '
              'to exit 0 on $_8u7TrialMergeRef\n'
              'stdout:\n${outcome.stdout}\n'
              'stderr:\n${outcome.stderr}',
        );
      },
      timeout: const Timeout(Duration(minutes: 31)),
      skip: _skipNestedCleanupInCiDartTest,
    );

    test(
      'AGENTS.md records tentura-pl4 landing gate acceptance beside prior trial merges',
      () {
        final agents = _repoFile('AGENTS.md').readAsStringSync();
        expect(
          agents,
          contains(_agentsPl4LandingComment),
          reason:
              'append $_agentsPl4LandingComment after tentura-uwq on '
              '$_8u7TrialMergeRef trial merge remediation',
        );
      },
    );
  });
}

File _repoFile(String relativePath) {
  final repo = repoRootFromServerPackage();
  final candidate = File('${repo.path}/$relativePath');
  if (!candidate.existsSync()) {
    throw StateError('Repo file not found: ${candidate.path}');
  }
  return candidate;
}
