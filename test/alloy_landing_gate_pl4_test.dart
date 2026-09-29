import 'dart:io';

import 'package:test/test.dart';

// tentura-pl4 landing gate acceptance (fix tentura-8u7)

/// Same paths as bead tentura-pl4 acceptance harness.
const kPl4AcceptanceTestPaths = [
  'packages/server/test/architecture/tentura_pl4_landing_check_test.dart',
  'packages/server/test/architecture/tentura_pl4_di_acceptance_probe_test.dart',
  'test/alloy_landing_gate_pl4_test.dart',
];

const _pl4LandingGateMarker =
    'tentura-pl4 landing gate acceptance (fix tentura-8u7)';

const _8u7LandingGateMarker =
    'tentura-8u7 landing gate acceptance (parent tentura-8u7)';

const _8u7LandingCheckRelative =
    'packages/server/test/architecture/tentura_8u7_landing_check_test.dart';

File _repoFile(String relativePath) => File(relativePath);

void main() {
  group('alloy landing gate (tentura-pl4)', () {
    test('pl4 acceptance test files declare pl4 landing gate markers', () {
      for (final path in kPl4AcceptanceTestPaths) {
        final file = _repoFile(path);
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
          contains('fix tentura-8u7'),
          reason: '$path must reference parent landing bead tentura-8u7',
        );
      }
    });

    test(
      'tentura-8u7 acceptance paths include pl4 landing gate for non-pg remediation',
      () {
        final gate = _repoFile(_8u7LandingCheckRelative);
        expect(
          gate.existsSync(),
          isTrue,
          reason: 'missing $_8u7LandingCheckRelative',
        );
        final source = gate.readAsStringSync();
        expect(
          source,
          contains(_8u7LandingGateMarker),
          reason: '8u7 gate test must remain the parent landing marker',
        );
        for (final path in kPl4AcceptanceTestPaths) {
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
                'after tentura-pl4 lands',
          );
        }
      },
    );
  });
}
