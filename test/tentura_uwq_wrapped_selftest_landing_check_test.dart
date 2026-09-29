import 'dart:io';

import 'package:test/test.dart';

// tentura-uwq landing gate acceptance (fix tentura-ah4 wrapped selftest)

/// Alloy tentura-uwq — same path as bead acceptance harness.
const kUwqAcceptanceTestPaths = [
  'test/tentura_uwq_wrapped_selftest_landing_check_test.dart',
];

const _uwqLandingGateMarker =
    'tentura-uwq landing gate acceptance (fix tentura-ah4 wrapped selftest)';

const _parentLandingMarker = 'fix tentura-ah4';

const _j0qGateTestPath =
    'packages/server/test/architecture/tentura_j0q_landing_check_test.dart';

const _agentsUwqLandingComment =
    '<!-- tentura-uwq landing gate acceptance (fix tentura-ah4 wrapped selftest) -->';

const _ah4TrialMergeRef = 'alloy/tentura-ah4';

const _wrappedSelftestRelative = 'scripts/run_with_test_cleanup_selftest.sh';

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
  group('tentura-uwq wrapped selftest landing check (fix tentura-ah4)', () {
    test('uwq acceptance test paths declare tentura-uwq landing gate markers', () {
      for (final path in kUwqAcceptanceTestPaths) {
        final file = _repoFile(path);
        expect(file.existsSync(), isTrue, reason: 'missing acceptance path $path');
        final source = file.readAsStringSync();
        expect(
          source,
          contains(_uwqLandingGateMarker),
          reason:
              '$path must tag the uwq landing gate for Alloy trial-merge tracking',
        );
        expect(
          source,
          contains(_parentLandingMarker),
          reason: '$path must reference parent landing bead tentura-ah4',
        );
      }
    });

    test(
      'tentura-j0q landing gate lists uwq acceptance paths for tentura-ah4 trial merge',
      () {
        final gate = _repoFile(_j0qGateTestPath);
        expect(gate.existsSync(), isTrue, reason: 'missing $_j0qGateTestPath');
        final source = gate.readAsStringSync();
        for (final path in kUwqAcceptanceTestPaths) {
          expect(
            source.contains("'$path'"),
            isTrue,
            reason:
                'kJ0qTrackedLaterAcceptanceTestPaths must list $path after tentura-uwq lands',
          );
        }
      },
    );

    test(
      'AGENTS.md records tentura-uwq landing gate acceptance beside prior trial merges',
      () {
        final agents = _repoFile('AGENTS.md').readAsStringSync();
        expect(
          agents,
          contains(_agentsUwqLandingComment),
          reason:
              'append $_agentsUwqLandingComment after tentura-kd9 on '
              'alloy/tentura-ah4 trial merge',
        );
      },
    );

    test(
      'bead acceptance: wrapped selftest exits 0 on alloy/tentura-ah4 trial merge',
      () {
        final outcome = runUwqBeadAcceptanceOnAh4TrialMerge();
        expect(
          outcome.exitCode,
          0,
          reason:
              'tentura-uwq requires '
              '`bash $_wrappedSelftestRelative` '
              'to exit 0 on $_ah4TrialMergeRef\n'
              'stdout:\n${outcome.stdout}\n'
              'stderr:\n${outcome.stderr}',
        );
        expect(
          outcome.combined,
          contains('passed=16 failed=0'),
          reason:
              'wrapped selftest must finish with zero failures on the ah4 trial merge\n'
              'combined output:\n${outcome.combined}',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'bead acceptance: nested wrapped selftest exits 0 on alloy/tentura-ah4',
      () {
        final outcome = runUwqNestedWrappedBeadAcceptanceOnAh4TrialMerge();
        expect(
          outcome.exitCode,
          0,
          reason:
              'tentura-uwq requires '
              '`./scripts/run_with_test_cleanup.sh --timeout 10m -- '
              'bash $_wrappedSelftestRelative` '
              'to exit 0 on $_ah4TrialMergeRef\n'
              'stdout:\n${outcome.stdout}\n'
              'stderr:\n${outcome.stderr}',
        );
        expect(
          outcome.combined,
          contains('passed=16 failed=0'),
          reason:
              'nested wrapped selftest must finish with zero failures '
              'when Alloy runs acceptance inside an outer wrapper\n'
              'combined output:\n${outcome.combined}',
        );
      },
      timeout: const Timeout(Duration(minutes: 12)),
      skip: _skipNestedCleanupInCiDartTest,
    );
  });
}

/// Runs tentura-uwq bead acceptance on a detached worktree at [_ah4TrialMergeRef].
({int exitCode, String stdout, String stderr, String combined})
runUwqBeadAcceptanceOnAh4TrialMerge() {
  return _runInAh4TrialMergeWorktree((repo, nestedTmp) {
    final result = Process.runSync(
      'bash',
      [_wrappedSelftestRelative],
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

/// Runs nested wrapped selftest the way Alloy does on the ah4 trial merge.
({int exitCode, String stdout, String stderr, String combined})
runUwqNestedWrappedBeadAcceptanceOnAh4TrialMerge() {
  return _runInAh4TrialMergeWorktree((repo, nestedTmp) {
    final wrapper = File('${repo.path}/scripts/run_with_test_cleanup.sh');
    final result = Process.runSync(
      wrapper.path,
      [
        '--timeout',
        '10m',
        '--',
        'bash',
        _wrappedSelftestRelative,
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
  final worktreeParent = Directory.systemTemp.createTempSync('tentura-uwq-ah4-wt-');
  final worktreePath = '${worktreeParent.path}/checkout';
  final nestedTmp = Directory.systemTemp.createTempSync('tentura-uwq-ah4-tmp-');
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
