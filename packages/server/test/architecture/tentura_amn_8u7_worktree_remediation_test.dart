// tentura-amn landing gate acceptance (fix tentura-8u7 worktree for tentura-pl4)

import 'dart:io';

import 'package:test/test.dart';

import '../support/server_ci_lint_gate_harness.dart';

/// Alloy tentura-amn — git janitorial on the checked-out alloy/tentura-8u7 worktree.
const kAmnAcceptanceTestPaths = [
  'test/architecture/tentura_amn_8u7_worktree_remediation_test.dart',
  'test/alloy_landing_gate_amn_test.dart',
];

const _amnLandingGateMarker =
    'tentura-amn landing gate acceptance (fix tentura-8u7 worktree for tentura-pl4)';

const _parentPl4Marker = 'fix tentura-8u7 worktree for tentura-pl4';

const _diRemediationCommit = '3149b0451';

const _8u7BranchRef = 'alloy/tentura-8u7';

const _8u7CheckedOutWorktreeRelative = '.alloy/worktrees/tentura-8u7';

/// Focused non-pg probes that must exist on alloy/tentura-8u7 after remediation.
const kPl4DiProbeTestPaths = [
  'test/app/di_test_env_smoke_test.dart',
  'test/app/help_offer_repository_di_binding_test.dart',
  'test/app/closure_ports_di_smoke_test.dart',
];

/// Leftover paths from the abandoned remediation attempt (must not remain dirty).
const k8u7AbandonedRemediationPaths = [
  'packages/server/test/app/closure_ports_di_smoke_test.dart',
  'packages/server/lib/data/repository/mock/band_candidate_repository_mock.dart',
  'packages/server/lib/data/repository/mock/commitment_repository_mock.dart',
];

void main() {
  group('tentura-amn 8u7 worktree remediation (fix tentura-pl4)', () {
    test('amn acceptance test paths declare amn landing gate markers', () {
      for (final path in kAmnAcceptanceTestPaths) {
        final file = _acceptanceFile(path);
        expect(file.existsSync(), isTrue, reason: 'missing acceptance path $path');
        final source = file.readAsStringSync();
        expect(
          source,
          contains(_amnLandingGateMarker),
          reason:
              '$path must tag the amn landing gate for Alloy trial-merge tracking',
        );
        expect(
          source,
          contains(_parentPl4Marker),
          reason: '$path must reference parent bead tentura-pl4 / tentura-8u7',
        );
      }
    });

    test(
      'bead acceptance: $_diRemediationCommit is an ancestor of $_8u7BranchRef',
      () {
        final repo = repoRootFromServerPackage();
        final result = Process.runSync(
          'git',
          ['merge-base', '--is-ancestor', _diRemediationCommit, _8u7BranchRef],
          workingDirectory: repo.path,
        );
        expect(
          result.exitCode,
          0,
          reason:
              'alloy/tentura-8u7 must fast-forward past $_diRemediationCommit '
              '(Environment.test DI remediation) before tentura-pl4 landing\n'
              'stdout:\n${result.stdout}\n'
              'stderr:\n${result.stderr}',
        );
      },
    );

    test(
      'bead acceptance: checked-out $_8u7CheckedOutWorktreeRelative worktree is clean',
      () {
        final repo = repoRootFromServerPackage();
        final worktreePath = _alloy8u7CheckedOutWorktreePath(repo);
        expect(
          worktreePath,
          isNotNull,
          reason:
              'missing checked-out $_8u7BranchRef worktree — Alloy keeps it at '
              '$_8u7CheckedOutWorktreeRelative under the main checkout or via '
              'git worktree list',
        );
        final worktree = Directory(worktreePath!);
        final status = Process.runSync(
          'git',
          ['-C', worktree.path, 'status', '--porcelain'],
          workingDirectory: repo.path,
        );
        expect(status.exitCode, 0, reason: status.stderr.toString());
        final porcelain = (status.stdout as String).trim();
        expect(
          porcelain,
          isEmpty,
          reason:
              'abandoned remediation leftovers block ff-only merge on $_8u7BranchRef; '
              'discard staged/untracked paths and leave a clean tree\n'
              'git status --porcelain:\n$porcelain',
        );
      },
    );

    test(
      'bead acceptance: no abandoned remediation paths remain only in the worktree index',
      () {
        final repo = repoRootFromServerPackage();
        final worktreePath = _alloy8u7CheckedOutWorktreePath(repo);
        expect(
          worktreePath,
          isNotNull,
          reason: 'missing checked-out $_8u7BranchRef',
        );
        final worktree = worktreePath!;
        for (final relative in k8u7AbandonedRemediationPaths) {
          final pathInWorktree = '$worktree/$relative';
          final file = File(pathInWorktree);
          if (!file.existsSync()) {
            continue;
          }
          final tracked = Process.runSync(
            'git',
            ['-C', worktree, 'ls-files', '--error-unmatch', relative],
            workingDirectory: repo.path,
          );
          expect(
            tracked.exitCode,
            0,
            reason:
                '$relative must be tracked at $_diRemediationCommit on $_8u7BranchRef, '
                'not left as a superseded untracked copy in the worktree',
          );
        }
      },
    );

    test(
      'bead acceptance: pl4 DI probe paths exist on $_8u7BranchRef',
      () {
        final repo = repoRootFromServerPackage();
        for (final path in kPl4DiProbeTestPaths) {
          final repoRelative = 'packages/server/$path';
          final show = Process.runSync(
            'git',
            ['show', '$_8u7BranchRef:$repoRelative'],
            workingDirectory: repo.path,
          );
          expect(
            show.exitCode,
            0,
            reason:
                '$_8u7BranchRef must contain $path after ff past $_diRemediationCommit\n'
                'stderr:\n${show.stderr}',
          );
        }
      },
    );

    test(
      'bead acceptance: wrapped pl4 DI probe tests exit 0 on $_8u7BranchRef',
      () {
        final outcome = runPl4DiProbeOn8u7BranchRef();
        expect(
          outcome.exitCode,
          0,
          reason:
              'tentura-pl4 requires Environment.test DI probes on $_8u7BranchRef '
              'before non-pg landing\n'
              'stdout:\n${outcome.stdout}\n'
              'stderr:\n${outcome.stderr}',
        );
      },
      timeout: const Timeout(Duration(minutes: 8)),
    );
  });
}

/// Path of the long-lived checkout for [_8u7BranchRef], from `git worktree list`.
String? _alloy8u7CheckedOutWorktreePath(Directory repo) {
  final result = Process.runSync(
    'git',
    ['worktree', 'list', '--porcelain'],
    workingDirectory: repo.path,
  );
  if (result.exitCode != 0) {
    return null;
  }
  final branchMarker = 'branch refs/heads/$_8u7BranchRef';
  String? pendingWorktree;
  for (final line in (result.stdout as String).split('\n')) {
    if (line.startsWith('worktree ')) {
      pendingWorktree = line.substring('worktree '.length);
    } else if (line == branchMarker && pendingWorktree != null) {
      return pendingWorktree;
    } else if (line.isEmpty) {
      pendingWorktree = null;
    }
  }
  return null;
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

({int exitCode, String stdout, String stderr}) runPl4DiProbeOn8u7BranchRef() {
  return _runIn8u7BranchWorktree((serverPackage, nestedTmp) {
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

T _runIn8u7BranchWorktree<T>(_8u7WorktreeRun<T> run) {
  final hostRepo = repoRootFromServerPackage();
  final worktreeParent =
      Directory.systemTemp.createTempSync('tentura-amn-8u7-wt-');
  final worktreePath = '${worktreeParent.path}/checkout';
  final nestedTmp = Directory.systemTemp.createTempSync('tentura-amn-8u7-tmp-');
  try {
    final add = Process.runSync(
      'git',
      ['worktree', 'add', '--detach', worktreePath, _8u7BranchRef],
      workingDirectory: hostRepo.path,
    );
    if (add.exitCode != 0) {
      throw StateError(
        'git worktree add $_8u7BranchRef failed:\n'
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
