import 'dart:io';

import 'package:test/test.dart';

// tentura-3i0m landing gate acceptance (fix tentura-8u7)

/// Same paths as bead tentura-3i0m acceptance harness.
const k3i0mAcceptanceTestPaths = [
  'packages/server/test/architecture/tentura_3i0m_landing_check_test.dart',
  'test/alloy_landing_gate_3i0m_test.dart',
];

const k3i0mBeadAcceptanceTestPaths = [
  'packages/server/test/architecture/tentura_pl4_di_acceptance_probe_test.dart',
  'packages/server/test/architecture/tentura_8u7_landing_check_test.dart',
  'packages/server/test/architecture/tentura_pl4_landing_check_test.dart',
  'packages/server/test/architecture/tentura_amn_8u7_worktree_remediation_test.dart',
];

const _3i0mLandingGateMarker =
    'tentura-3i0m landing gate acceptance (fix tentura-8u7)';

const _8u7LandingCheckRelative =
    'packages/server/test/architecture/tentura_8u7_landing_check_test.dart';

const _8u7TrialMergeRef = 'alloy/tentura-8u7';

File _repoFile(String relativePath) => File(relativePath);

void main() {
  group('alloy landing gate (tentura-3i0m)', () {
    test('3i0m acceptance test files declare 3i0m landing gate markers', () {
      for (final path in k3i0mAcceptanceTestPaths) {
        final file = _repoFile(path);
        expect(file.existsSync(), isTrue, reason: 'missing acceptance path $path');
        final source = file.readAsStringSync();
        expect(
          source,
          contains(_3i0mLandingGateMarker),
          reason:
              '$path must tag the 3i0m landing gate for Alloy trial-merge tracking',
        );
        expect(
          source,
          contains('fix tentura-8u7'),
          reason: '$path must reference parent landing bead tentura-8u7',
        );
      }
    });

    test(
      'tentura-8u7 acceptance paths include 3i0m bead harness for landing remediation',
      () {
        final gate = _repoFile(_8u7LandingCheckRelative);
        expect(
          gate.existsSync(),
          isTrue,
          reason: 'missing $_8u7LandingCheckRelative',
        );
        final source = gate.readAsStringSync();
        for (final path in k3i0mBeadAcceptanceTestPaths) {
          final serverRelative = path.startsWith('packages/server/')
              ? path.substring('packages/server/'.length)
              : path;
          final listed = source.contains("'$path'") ||
              source.contains("'$serverRelative'");
          expect(
            listed,
            isTrue,
            reason:
                'k8u7AcceptanceTestPaths must list $path (or $serverRelative) '
                'after tentura-3i0m lands on $_8u7TrialMergeRef',
          );
        }
        final server3i0m =
            'test/architecture/tentura_3i0m_landing_check_test.dart';
        expect(
          source.contains("'$server3i0m'") ||
              source.contains(
                "'packages/server/test/architecture/tentura_3i0m_landing_check_test.dart'",
              ),
          isTrue,
          reason:
              'k8u7AcceptanceTestPaths must list tentura_3i0m_landing_check_test.dart',
        );
      },
    );
  });
}
