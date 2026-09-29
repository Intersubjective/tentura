// tentura-pl4 landing gate acceptance (fix tentura-8u7)

import 'dart:io';

import 'package:test/test.dart';

import '../support/server_ci_lint_gate_harness.dart';

/// Focused non-pg probes for Environment.test DI on alloy/tentura-8u7.
const kPl4DiProbeTestPaths = [
  'test/app/di_test_env_smoke_test.dart',
  'test/app/help_offer_repository_di_binding_test.dart',
  'test/app/closure_ports_di_smoke_test.dart',
];

const _8u7TrialMergeRef = 'alloy/tentura-8u7';

void main() {
  group('tentura-pl4 DI acceptance probe (fix tentura-8u7)', () {
    test('pl4 DI probe test paths exist on the host server package', () {
      for (final path in kPl4DiProbeTestPaths) {
        expect(
          File(path).existsSync(),
          isTrue,
          reason:
              'tentura-8u7 remediation must ship $path before non-pg landing',
        );
      }
    });

    test('closure_ports_di_smoke_test boots DI with smokeTestEnv', () {
      final source =
          File('test/app/closure_ports_di_smoke_test.dart').readAsStringSync();
      expect(
        source,
        contains('smokeTestEnv()'),
        reason:
            'Environment.test DI smoke must use hermetic smokeTestEnv, not '
            'emailAuthUnconfiguredTestEnv',
      );
      expect(
        source,
        isNot(contains('emailAuthUnconfiguredTestEnv()')),
        reason: 'emailAuthUnconfiguredTestEnv leaves dev/prod-only ports unbound',
      );
    });

    test(
      'bead acceptance: wrapped pl4 DI probe tests exit 0 on host tree',
      () {
        final outcome = runPl4DiProbeOnHostTree();
        expect(
          outcome.exitCode,
          0,
          reason:
              'pl4 DI probe must pass before alloy/tentura-8u7 non-pg landing\n'
              'stdout:\n${outcome.stdout}\n'
              'stderr:\n${outcome.stderr}',
        );
      },
      timeout: const Timeout(Duration(minutes: 6)),
    );

    test(
      'bead acceptance: wrapped pl4 DI probe tests exit 0 on alloy/tentura-8u7',
      () {
        final outcome = runPl4DiProbeOn8u7TrialMerge();
        expect(
          outcome.exitCode,
          0,
          reason:
              'tentura-pl4 requires Environment.test DI probes to pass on '
              '$_8u7TrialMergeRef before non-pg landing\n'
              'stdout:\n${outcome.stdout}\n'
              'stderr:\n${outcome.stderr}',
        );
      },
      timeout: const Timeout(Duration(minutes: 8)),
    );
  });
}

/// Runs the pl4 DI probe files from the current server package checkout.
({int exitCode, String stdout, String stderr}) runPl4DiProbeOnHostTree() {
  return _runWrappedDartTest(
    workingDirectory: serverPackageRoot(),
    testArgs: kPl4DiProbeTestPaths,
  );
}

/// Runs the pl4 DI probe files inside a detached worktree at [_8u7TrialMergeRef].
({int exitCode, String stdout, String stderr}) runPl4DiProbeOn8u7TrialMerge() {
  return _runIn8u7TrialMergeWorktree((serverPackage, nestedTmp) {
    final result = Process.runSync(
      testCleanupWrapperFromServerPackage().path,
      [
        '--timeout',
        '6m',
        '--',
        'dart',
        'test',
        ...kPl4DiProbeTestPaths,
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
  });
}

({int exitCode, String stdout, String stderr}) _runWrappedDartTest({
  required Directory workingDirectory,
  required List<String> testArgs,
}) {
  final nestedTmp = Directory.systemTemp.createTempSync('tentura-pl4-probe-');
  try {
    final result = Process.runSync(
      testCleanupWrapperFromServerPackage().path,
      [
        '--timeout',
        '5m',
        '--',
        'dart',
        'test',
        ...testArgs,
      ],
      workingDirectory: workingDirectory.path,
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

/// A fresh worktree has no gitignored generated sources (`di.config.dart`,
/// `*.g.dart`); the DI probe tests cannot compile without them.
void _generateIgnoredSources(Directory serverPackage) {
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
      'build_runner build failed in 8u7 trial-merge worktree:\n'
      '${result.stdout}\n${result.stderr}',
    );
  }
}

typedef _8u7WorktreeRun<T> = T Function(
  Directory serverPackage,
  Directory nestedTmp,
);

T _runIn8u7TrialMergeWorktree<T>(_8u7WorktreeRun<T> run) {
  final hostRepo = repoRootFromServerPackage();
  final worktreeParent =
      Directory.systemTemp.createTempSync('tentura-pl4-8u7-wt-');
  final worktreePath = '${worktreeParent.path}/checkout';
  final nestedTmp = Directory.systemTemp.createTempSync('tentura-pl4-8u7-tmp-');
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
    _generateIgnoredSources(serverPackage);
    return run(serverPackage, nestedTmp);
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
