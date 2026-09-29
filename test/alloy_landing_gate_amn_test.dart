import 'dart:io';

import 'package:test/test.dart';

// tentura-amn landing gate acceptance (fix tentura-8u7 worktree for tentura-pl4)

/// Same paths as bead tentura-amn acceptance harness.
const kAmnAcceptanceTestPaths = [
  'packages/server/test/architecture/tentura_amn_8u7_worktree_remediation_test.dart',
  'test/alloy_landing_gate_amn_test.dart',
];

const _amnLandingGateMarker =
    'tentura-amn landing gate acceptance (fix tentura-8u7 worktree for tentura-pl4)';

const _parentPl4Marker = 'fix tentura-8u7 worktree for tentura-pl4';

const _diRemediationCommit = '3149b0451';

const _8u7BranchRef = 'alloy/tentura-8u7';

File _repoFile(String relativePath) => File(relativePath);

void main() {
  group('alloy landing gate (tentura-amn)', () {
    test('amn acceptance test files declare amn landing gate markers', () {
      for (final path in kAmnAcceptanceTestPaths) {
        final file = _repoFile(path);
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
          reason: '$path must reference tentura-pl4 / tentura-8u7 remediation',
        );
      }
    });

    test(
      'bead acceptance: $_diRemediationCommit is an ancestor of $_8u7BranchRef',
      () {
        final repo = _repoRoot();
        final result = Process.runSync(
          'git',
          ['merge-base', '--is-ancestor', _diRemediationCommit, _8u7BranchRef],
          workingDirectory: repo.path,
        );
        expect(
          result.exitCode,
          0,
          reason:
              'alloy/tentura-8u7 must include the landed DI remediation before pl4 lands\n'
              'stderr:\n${result.stderr}',
        );
      },
    );
  });
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
