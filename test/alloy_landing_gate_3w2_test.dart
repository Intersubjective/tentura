import 'dart:io';

import 'package:test/test.dart';

// tentura-3w2 landing gate acceptance (fix tentura-pl4)

/// Same paths as bead tentura-3w2 acceptance harness.
const k3w2AcceptanceTestPaths = [
  'packages/server/test/architecture/tentura_3w2_landing_check_test.dart',
  'test/alloy_landing_gate_3w2_test.dart',
];

const _3w2LandingGateMarker =
    'tentura-3w2 landing gate acceptance (fix tentura-pl4)';

const _8u7LandingCheckRelative =
    'packages/server/test/architecture/tentura_8u7_landing_check_test.dart';

const _8u7TrialMergeRef = 'alloy/tentura-8u7';

File _repoFile(String relativePath) => File(relativePath);

void main() {
  group('alloy landing gate (tentura-3w2)', () {
    test('3w2 acceptance test files declare 3w2 landing gate markers', () {
      for (final path in k3w2AcceptanceTestPaths) {
        final file = _repoFile(path);
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
          contains('fix tentura-pl4'),
          reason: '$path must reference parent landing bead tentura-pl4',
        );
      }
    });

    test(
      'tentura-8u7 acceptance paths include 3w2 landing gate for stale-ref remediation',
      () {
        final gate = _repoFile(_8u7LandingCheckRelative);
        expect(
          gate.existsSync(),
          isTrue,
          reason: 'missing $_8u7LandingCheckRelative',
        );
        final source = gate.readAsStringSync();
        const server3w2 =
            'test/architecture/tentura_3w2_landing_check_test.dart';
        expect(
          source.contains("'$server3w2'") ||
              source.contains(
                "'packages/server/test/architecture/tentura_3w2_landing_check_test.dart'",
              ),
          isTrue,
          reason:
              'k8u7AcceptanceTestPaths must list $server3w2 after tentura-3w2 '
              'lands on $_8u7TrialMergeRef',
        );
      },
    );
  });
}
