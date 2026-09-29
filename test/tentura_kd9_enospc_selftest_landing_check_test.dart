import 'dart:io';

import 'package:test/test.dart';

// tentura-kd9 landing gate acceptance (fix tentura-ah4 enospc selftest)

/// Alloy tentura-kd9 — same path as bead acceptance harness.
const kKd9AcceptanceTestPaths = [
  'test/tentura_kd9_enospc_selftest_landing_check_test.dart',
];

const _kd9LandingGateMarker =
    'tentura-kd9 landing gate acceptance (fix tentura-ah4 enospc selftest)';

const _parentLandingMarker = 'fix tentura-ah4';

const _j0qGateTestPath =
    'packages/server/test/architecture/tentura_j0q_landing_check_test.dart';

const _agentsKd9LandingComment =
    '<!-- tentura-kd9 landing gate acceptance (fix tentura-ah4 enospc selftest) -->';

const _ah4TrialMergeRef = 'alloy/tentura-ah4';

const _enospcSelftestRelative = 'scripts/run_with_test_cleanup_enospc_selftest.sh';

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
  group('tentura-kd9 enospc selftest landing check (fix tentura-ah4)', () {
    test('kd9 acceptance test paths declare tentura-kd9 landing gate markers', () {
      for (final path in kKd9AcceptanceTestPaths) {
        final file = _repoFile(path);
        expect(file.existsSync(), isTrue, reason: 'missing acceptance path $path');
        final source = file.readAsStringSync();
        expect(
          source,
          contains(_kd9LandingGateMarker),
          reason:
              '$path must tag the kd9 landing gate for Alloy trial-merge tracking',
        );
        expect(
          source,
          contains(_parentLandingMarker),
          reason: '$path must reference parent landing bead tentura-ah4',
        );
      }
    });

    test(
      'tentura-j0q landing gate lists kd9 acceptance paths for tentura-ah4 trial merge',
      () {
        final gate = _repoFile(_j0qGateTestPath);
        expect(gate.existsSync(), isTrue, reason: 'missing $_j0qGateTestPath');
        final source = gate.readAsStringSync();
        for (final path in kKd9AcceptanceTestPaths) {
          expect(
            source.contains("'$path'"),
            isTrue,
            reason:
                'kJ0qAcceptanceTestPaths must list $path after tentura-kd9 lands',
          );
        }
      },
    );

    test(
      'AGENTS.md records tentura-kd9 landing gate acceptance beside prior trial merges',
      () {
        final agents = _repoFile('AGENTS.md').readAsStringSync();
        expect(
          agents,
          contains(_agentsKd9LandingComment),
          reason:
              'append $_agentsKd9LandingComment after tentura-j0q on '
              'alloy/tentura-ah4 trial merge',
        );
      },
    );

    test(
      'bead acceptance: enospc selftest exits 0 on alloy/tentura-ah4 trial merge',
      () {
        final outcome = runKd9BeadAcceptanceOnAh4TrialMerge();
        expect(
          outcome.exitCode,
          0,
          reason:
              'tentura-kd9 requires '
              '`bash $_enospcSelftestRelative` '
              'to exit 0 on $_ah4TrialMergeRef\n'
              'stdout:\n${outcome.stdout}\n'
              'stderr:\n${outcome.stderr}',
        );
        expect(
          outcome.combined,
          contains('passed=26 failed=0'),
          reason:
              'enospc selftest must finish with zero failures on the ah4 trial merge\n'
              'combined output:\n${outcome.combined}',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'bead acceptance: nested wrapped enospc selftest exits 0 on alloy/tentura-ah4',
      () {
        final outcome = runKd9NestedWrappedBeadAcceptanceOnAh4TrialMerge();
        expect(
          outcome.exitCode,
          0,
          reason:
              'tentura-kd9 requires '
              '`./scripts/run_with_test_cleanup.sh --timeout 10m -- '
              'bash $_enospcSelftestRelative` '
              'to exit 0 on $_ah4TrialMergeRef\n'
              'stdout:\n${outcome.stdout}\n'
              'stderr:\n${outcome.stderr}',
        );
        expect(
          outcome.combined,
          contains('passed=26 failed=0'),
          reason:
              'nested wrapped enospc selftest must finish with zero failures '
              'when Alloy runs acceptance inside an outer wrapper\n'
              'combined output:\n${outcome.combined}',
        );
      },
      timeout: const Timeout(Duration(minutes: 12)),
      skip: _skipNestedCleanupInCiDartTest,
    );
  });
}

/// Runs tentura-kd9 bead acceptance on a detached worktree at [ _ah4TrialMergeRef ].
({int exitCode, String stdout, String stderr, String combined})
runKd9BeadAcceptanceOnAh4TrialMerge() {
  return _runInAh4TrialMergeWorktree((repo, nestedTmp) {
    final result = Process.runSync(
      'bash',
      [_enospcSelftestRelative],
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
  });
}

/// Runs nested wrapped enospc selftest the way Alloy does on the ah4 trial merge.
({int exitCode, String stdout, String stderr, String combined})
runKd9NestedWrappedBeadAcceptanceOnAh4TrialMerge() {
  return _runInAh4TrialMergeWorktree((repo, nestedTmp) {
    final wrapper = File('${repo.path}/scripts/run_with_test_cleanup.sh');
    final result = Process.runSync(
      wrapper.path,
      [
        '--timeout',
        '10m',
        '--',
        'bash',
        _enospcSelftestRelative,
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
  });
}

typedef _Ah4WorktreeRun<T> = T Function(Directory repo, Directory nestedTmp);

T _runInAh4TrialMergeWorktree<T>(_Ah4WorktreeRun<T> run) {
  final hostRepo = _repoRoot();
  final worktreeParent = Directory.systemTemp.createTempSync('tentura-kd9-ah4-wt-');
  final worktreePath = '${worktreeParent.path}/checkout';
  final nestedTmp = Directory.systemTemp.createTempSync('tentura-kd9-ah4-tmp-');
  try {
    final add = Process.runSync(
      'git',
      ['worktree', 'add', '--detach', worktreePath, _ah4TrialMergeRef],
      workingDirectory: hostRepo.path,
    );
    if (add.exitCode != 0) {
      throw StateError(
        'git worktree add $_ah4TrialMergeRef failed:\n'
        '${add.stdout}\n${add.stderr}',
      );
    }
    return run(Directory(worktreePath), nestedTmp);
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
