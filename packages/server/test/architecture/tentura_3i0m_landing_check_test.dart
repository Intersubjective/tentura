// tentura-3i0m landing gate acceptance (fix tentura-8u7)

import 'dart:io';

import 'package:test/test.dart';

import '../support/server_ci_lint_gate_harness.dart';

const k3i0mAcceptanceTestPaths = [
  'test/architecture/tentura_3i0m_landing_check_test.dart',
  'test/alloy_landing_gate_3i0m_test.dart',
];

const _3i0mLandingGateMarker =
    'tentura-3i0m landing gate acceptance (fix tentura-8u7)';

const _parentLandingMarker = 'fix tentura-8u7';

const _8u7LandingCheckRelative =
    'test/architecture/tentura_8u7_landing_check_test.dart';

const _8u7TrialMergeRef = 'alloy/tentura-8u7';

const _agents3i0mLandingComment =
    '<!-- tentura-3i0m landing gate acceptance (fix tentura-8u7) -->';

const _harness3i0mRunnerName =
    'run3i0mAcceptanceFourFileDartTestOn8u7TrialMerge';

void main() {
  group('tentura-3i0m landing check (fix tentura-8u7)', () {
    test('3i0m acceptance test paths declare 3i0m landing gate markers', () {
      for (final path in k3i0mAcceptanceTestPaths) {
        final file = _acceptanceFile(path);
        expect(
          file.existsSync(),
          isTrue,
          reason: 'missing acceptance path $path',
        );
        final source = file.readAsStringSync();
        expect(
          source,
          contains(_3i0mLandingGateMarker),
          reason:
              '$path must tag the 3i0m landing gate for Alloy trial-merge tracking',
        );
        expect(
          source,
          contains(_parentLandingMarker),
          reason: '$path must reference parent landing bead tentura-8u7',
        );
      }
    });

    test(
      'tentura-8u7 parent landing gate lists 3i0m bead acceptance paths',
      () {
        final source = File(
          '${serverPackageRoot().path}/$_8u7LandingCheckRelative',
        ).readAsStringSync();
        for (final path in k3i0mBeadAcceptanceTestPaths) {
          expect(
            source,
            contains("'$path'"),
            reason:
                '$_8u7LandingCheckRelative k8u7AcceptanceTestPaths must list '
                '$path so Alloy tentura-8u7 landing tracks tentura-3i0m bead '
                'harness',
          );
        }
        for (final path in k3i0mAcceptanceTestPaths) {
          if (path.startsWith('test/alloy_landing_gate')) {
            continue;
          }
          expect(
            source,
            contains("'$path'"),
            reason:
                '$_8u7LandingCheckRelative must list $path after tentura-3i0m '
                'lands on $_8u7TrialMergeRef',
          );
        }
      },
    );

    test(
      'bead acceptance paths exist on $_8u7TrialMergeRef at packages/server',
      () {
        final repo = repoRootFromServerPackage();
        // Alloy lands on the trial merge of the bead ref with the landing
        // target (host HEAD), as run3i0mAcceptanceFourFileDartTestOn8u7TrialMerge
        // does, so look the paths up in that merged tree.
        final trialMerge = Process.runSync(
          'git',
          ['merge-tree', '--write-tree', _8u7TrialMergeRef, 'HEAD'],
          workingDirectory: repo.path,
        );
        expect(
          trialMerge.exitCode,
          0,
          reason:
              'trial merge of $_8u7TrialMergeRef with HEAD must be clean\n'
              'stdout:\n${trialMerge.stdout}\nstderr:\n${trialMerge.stderr}',
        );
        final trialTree = (trialMerge.stdout as String)
            .split('\n')
            .first
            .trim();
        for (final path in k3i0mBeadAcceptanceTestPaths) {
          final repoRelative = 'packages/server/$path';
          final show = Process.runSync(
            'git',
            ['show', '$trialTree:$repoRelative'],
            workingDirectory: repo.path,
          );
          expect(
            show.exitCode,
            0,
            reason:
                '$_8u7TrialMergeRef trial merge must contain $path before '
                'tentura-3i0m '
                'landing\nstderr:\n${show.stderr}',
          );
        }
      },
    );

    test(
      'server CI harness exposes 3i0m four-file bead acceptance runner',
      () {
        final gateHarness = File(
          '${serverPackageRoot().path}/test/support/server_ci_lint_gate_harness.dart',
        ).readAsStringSync();
        expect(
          gateHarness,
          contains(_harness3i0mRunnerName),
          reason:
              'server_ci_lint_gate_harness must define $_harness3i0mRunnerName '
              'for tentura-3i0m alloy/tentura-8u7 landing acceptance',
        );
      },
    );

    test(
      'bead acceptance: wrapped four-file dart test exits 0 on $_8u7TrialMergeRef',
      () {
        final gateHarness = File(
          '${serverPackageRoot().path}/test/support/server_ci_lint_gate_harness.dart',
        ).readAsStringSync();
        expect(
          gateHarness,
          contains(_harness3i0mRunnerName),
          reason: '3i0m landing runner must exist before nested acceptance',
        );
        final outcome = run3i0mAcceptanceFourFileDartTestOn8u7TrialMerge();
        expect(
          outcome.exitCode,
          0,
          reason:
              'tentura-3i0m requires '
              '`./scripts/run_with_test_cleanup.sh --timeout 10m -- sh -c '
              "'cd packages/server && dart test "
              '${k3i0mBeadAcceptanceTestPaths.join(' ')}\'` '
              'to exit 0 on $_8u7TrialMergeRef\n'
              'stdout:\n${outcome.stdout}\n'
              'stderr:\n${outcome.stderr}',
        );
      },
      timeout: const Timeout(Duration(minutes: 11)),
      skip: bead8u7TransientStateSkip(),
    );

    test(
      'bead acceptance: $_8u7TrialMergeRef four-file harness exit code is zero',
      () {
        final outcome = run3i0mAcceptanceFourFileDartTestOn8u7TrialMerge();
        expect(
          outcome.exitCode,
          0,
          reason:
              'tentura-3i0m bead command must pass on $_8u7TrialMergeRef '
              'before landing\n'
              'stdout:\n${outcome.stdout}\n'
              'stderr:\n${outcome.stderr}',
        );
      },
      timeout: const Timeout(Duration(minutes: 11)),
      skip: bead8u7TransientStateSkip(),
    );

    test(
      'AGENTS.md records tentura-3i0m landing gate acceptance beside prior trial merges',
      () {
        final agents = _repoFile('AGENTS.md').readAsStringSync();
        expect(
          agents,
          contains(_agents3i0mLandingComment),
          reason:
              'append $_agents3i0mLandingComment after tentura-pl4 on '
              '$_8u7TrialMergeRef trial merge remediation',
        );
      },
    );
  });
}

File _acceptanceFile(String path) {
  final server = serverPackageRoot();
  final repo = repoRootFromServerPackage();
  final fromServer = File('${server.path}/$path');
  if (fromServer.existsSync()) {
    return fromServer;
  }
  return File('${repo.path}/$path');
}

File _repoFile(String relativePath) {
  final repo = repoRootFromServerPackage();
  final candidate = File('${repo.path}/$relativePath');
  if (!candidate.existsSync()) {
    throw StateError('Repo file not found: ${candidate.path}');
  }
  return candidate;
}
