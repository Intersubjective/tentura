// tentura-3w2 landing gate acceptance (fix tentura-pl4)

import 'dart:io';

import 'package:test/test.dart';

import '../support/server_ci_lint_gate_harness.dart';

/// Alloy tentura-3w2 — required check must not exercise a stale
/// `alloy/tentura-8u7` tip missing host landing fixes.
const k3w2AcceptanceTestPaths = [
  'test/architecture/tentura_3w2_landing_check_test.dart',
  'test/alloy_landing_gate_3w2_test.dart',
];

/// Leaf tests Alloy's bare `git worktree add --detach alloy/tentura-8u7`
/// harness must pass once the trial-merge ref includes the host tree.
const k3w2Bare8u7LeafTestPaths = [
  'test/data/repository/vote_user_friendship_lookup_test.dart',
  'test/architecture/tentura_olc_landing_check_test.dart',
];

const _3w2LandingGateMarker =
    'tentura-3w2 landing gate acceptance (fix tentura-pl4)';

const _parentLandingMarker = 'fix tentura-pl4';

const _8u7LandingCheckRelative =
    'test/architecture/tentura_8u7_landing_check_test.dart';

const _pl4LandingCheckRelative =
    'test/architecture/tentura_pl4_landing_check_test.dart';

const _8u7TrialMergeRef = 'alloy/tentura-8u7';

/// Observed stale tip when the required check detached HEAD without host fixes.
const _stale8u7TipSha = 'a4611edc4b3a23b104453e5726d58e09152eefff';

const _agents3w2LandingComment =
    '<!-- tentura-3w2 landing gate acceptance (fix tentura-pl4) -->';

const _harness3w2RunnerName = 'run3w2Bare8u7RequiredCheckLeafDartTest';

const _pl4DiProbeRelative =
    'test/architecture/tentura_pl4_di_acceptance_probe_test.dart';

const _harnessMergeHelperName = '_mergeLandingTargetInto8u7TrialMerge';

void main() {
  group('tentura-3w2 landing check (fix tentura-pl4)', () {
    test('3w2 acceptance test paths declare 3w2 landing gate markers', () {
      for (final path in k3w2AcceptanceTestPaths) {
        final file = _acceptanceFile(path);
        expect(file.existsSync(), isTrue, reason: 'missing acceptance path $path');
        final source = file.readAsStringSync();
        expect(
          source,
          contains(_3w2LandingGateMarker),
          reason:
              '$path must tag the 3w2 landing gate for Alloy trial-merge tracking',
        );
        expect(
          source,
          contains(_parentLandingMarker),
          reason: '$path must reference parent landing bead tentura-pl4',
        );
      }
    });

    test(
      'tentura-8u7 parent landing gate lists 3w2 acceptance paths',
      () {
        final source = File(
          '${serverPackageRoot().path}/$_8u7LandingCheckRelative',
        ).readAsStringSync();
        for (final path in k3w2AcceptanceTestPaths) {
          if (path.startsWith('test/alloy_landing_gate')) {
            continue;
          }
          expect(
            source,
            contains("'$path'"),
            reason:
                '$_8u7LandingCheckRelative k8u7AcceptanceTestPaths must list '
                '$path so Alloy tentura-8u7 landing tracks tentura-3w2',
          );
        }
      },
    );

    test(
      'tentura-pl4 parent landing gate lists 3w2 acceptance paths',
      () {
        final source = File(
          '${serverPackageRoot().path}/$_pl4LandingCheckRelative',
        ).readAsStringSync();
        for (final path in k3w2AcceptanceTestPaths) {
          if (path.startsWith('test/alloy_landing_gate')) {
            continue;
          }
          expect(
            source,
            contains("'$path'"),
            reason:
                '$_pl4LandingCheckRelative kPl4TrackedLaterAcceptanceTestPaths '
                'must list $path after tentura-3w2 lands on $_8u7TrialMergeRef',
          );
        }
      },
    );

    test(
      'bead acceptance: host HEAD is an ancestor of $_8u7TrialMergeRef',
      () {
        final repo = repoRootFromServerPackage();
        final result = Process.runSync(
          'git',
          ['merge-base', '--is-ancestor', 'HEAD', _8u7TrialMergeRef],
          workingDirectory: repo.path,
        );
        expect(
          result.exitCode,
          0,
          reason:
              'alloy/tentura-8u7 must include the host landing target (HEAD) '
              'so a bare detached worktree is not stuck at $_stale8u7TipSha\n'
              'stdout:\n${result.stdout}\n'
              'stderr:\n${result.stderr}',
        );
      },
      skip: bead8u7TransientStateSkip(),
    );

    test(
      'bead acceptance: $_8u7TrialMergeRef is not the stale required-check tip',
      () {
        final repo = repoRootFromServerPackage();
        final tip = Process.runSync(
          'git',
          ['rev-parse', _8u7TrialMergeRef],
          workingDirectory: repo.path,
        );
        expect(tip.exitCode, 0, reason: 'rev-parse $_8u7TrialMergeRef failed');
        expect(
          (tip.stdout as String).trim(),
          isNot(_stale8u7TipSha),
          reason:
              'required check must not keep testing detached HEAD $_stale8u7TipSha',
        );
      },
      skip: bead8u7TransientStateSkip(),
    );

    test(
      'pl4 DI probe trial-merge worktree merges host HEAD into $_8u7TrialMergeRef',
      () {
        final source = File(_pl4DiProbeRelative).readAsStringSync();
        expect(
          source,
          contains(_harnessMergeHelperName),
          reason:
              '$_pl4DiProbeRelative must call $_harnessMergeHelperName (or '
              'delegate to server_ci_lint_gate_harness trial merge) so Alloy '
              'bare detach matches tentura-3i0m landing semantics',
        );
      },
    );

    test(
      'server CI harness exposes 3w2 bare-8u7 required-check leaf runner',
      () {
        final gateHarness = File(
          '${serverPackageRoot().path}/test/support/server_ci_lint_gate_harness.dart',
        ).readAsStringSync();
        expect(
          gateHarness,
          contains(_harness3w2RunnerName),
          reason:
              'server_ci_lint_gate_harness must define $_harness3w2RunnerName '
              'for tentura-3w2 alloy/tentura-8u7 required-check acceptance',
        );
      },
    );

    test(
      'bead acceptance: wrapped leaf dart tests exit 0 on bare $_8u7TrialMergeRef',
      () {
        final outcome = run3w2Bare8u7RequiredCheckLeafDartTest();
        expect(
          outcome.exitCode,
          0,
          reason:
              'tentura-3w2 requires Alloy bare detach at $_8u7TrialMergeRef '
              'to pass ${k3w2Bare8u7LeafTestPaths.join(' ')}\n'
              'stdout:\n${outcome.stdout}\n'
              'stderr:\n${outcome.stderr}',
        );
      },
      timeout: const Timeout(Duration(minutes: 12)),
      skip: bead8u7TransientStateSkip(),
    );

    test(
      'AGENTS.md records tentura-3w2 landing gate acceptance beside prior trial merges',
      () {
        final agents = _repoFile('AGENTS.md').readAsStringSync();
        expect(
          agents,
          contains(_agents3w2LandingComment),
          reason:
              'append $_agents3w2LandingComment after tentura-30e on '
              '$_8u7TrialMergeRef trial merge remediation',
        );
      },
    );
  });
}

/// Runs [k3w2Bare8u7LeafTestPaths] inside a detached worktree at
/// [_8u7TrialMergeRef] without merging host HEAD — mirrors Alloy's required
/// check until tentura-3w2 remediation lands.
({int exitCode, String stdout, String stderr})
    run3w2Bare8u7RequiredCheckLeafDartTest() {
  return _runBare8u7DetachLeafDartTest(k3w2Bare8u7LeafTestPaths);
}

({int exitCode, String stdout, String stderr}) _runBare8u7DetachLeafDartTest(
  List<String> testPaths,
) {
  final hostRepo = repoRootFromServerPackage();
  final worktreeParent =
      Directory.systemTemp.createTempSync('tentura-3w2-8u7-wt-');
  final worktreePath = '${worktreeParent.path}/checkout';
  final nestedTmp = Directory.systemTemp.createTempSync('tentura-3w2-8u7-tmp-');
  try {
    final add = Process.runSync(
      'git',
      ['worktree', 'add', '--detach', worktreePath, _8u7TrialMergeRef],
      workingDirectory: hostRepo.path,
    );
    if (add.exitCode != 0) {
      throw StateError(
        'git worktree add $_8u7TrialMergeRef failed:\n'
        '${add.stdout}\n${add.stderr}',
      );
    }
    final serverPackage = Directory('$worktreePath/packages/server');
    _generateIgnoredSourcesBare8u7(serverPackage);
    final wrapper = File(
      '${hostRepo.path}/scripts/run_with_test_cleanup.sh',
    );
    final result = Process.runSync(
      wrapper.path,
      [
        '--timeout',
        '10m',
        '--',
        'dart',
        'test',
        ...testPaths,
      ],
      workingDirectory: serverPackage.path,
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
    Process.runSync(
      'git',
      ['worktree', 'remove', '--force', worktreePath],
      workingDirectory: hostRepo.path,
    );
    worktreeParent.deleteSync(recursive: true);
  }
}

void _generateIgnoredSourcesBare8u7(Directory serverPackage) {
  final result = Process.runSync(
    'dart',
    ['run', 'build_runner', 'build', '-d'],
    workingDirectory: serverPackage.path,
    environment: {
      ...Platform.environment,
      'DART_SUPPRESS_ANALYTICS': 'true',
    },
  );
  if (result.exitCode != 0) {
    throw StateError(
      'build_runner build failed in bare 8u7 worktree:\n'
      '${result.stdout}\n${result.stderr}',
    );
  }
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
