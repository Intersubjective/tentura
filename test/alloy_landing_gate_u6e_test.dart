import 'dart:io';

import 'package:test/test.dart';

// tentura-u6e landing gate acceptance (fix tentura-5zq)

/// Same paths as bead tentura-u6e acceptance harness.
const kU6eAcceptanceTestPaths = [
  'packages/server/test/architecture/tentura_u6e_landing_check_test.dart',
  'test/alloy_landing_gate_u6e_test.dart',
];

const _u6eLandingGateMarker =
    'tentura-u6e landing gate acceptance (fix tentura-5zq)';

const _5zqLandingGateMarker =
    'tentura-5zq landing gate acceptance (parent tentura-617.3)';

File _repoFile(String relativePath) => File(relativePath);

void main() {
  group('alloy landing gate (tentura-u6e)', () {
    test('u6e acceptance test files declare u6e landing gate markers', () {
      for (final path in kU6eAcceptanceTestPaths) {
        final file = _repoFile(path);
        expect(file.existsSync(), isTrue, reason: 'missing acceptance path $path');
        final source = file.readAsStringSync();
        expect(
          source,
          contains(_u6eLandingGateMarker),
          reason:
              '$path must tag the u6e landing gate for Alloy trial-merge tracking',
        );
        expect(
          source,
          contains('fix tentura-5zq'),
          reason: '$path must reference parent landing bead tentura-5zq',
        );
      }
    });

    test(
      'tentura-5zq acceptance paths include u6e landing gate for non-pg remediation',
      () {
        final source = _repoFile(
          'packages/server/test/architecture/tentura_5zq_server_ci_analyze_gate_test.dart',
        ).readAsStringSync();
        expect(
          source,
          contains(_5zqLandingGateMarker),
          reason: '5zq gate test must remain the parent landing marker',
        );
        for (final path in kU6eAcceptanceTestPaths) {
          final serverRelative = path.startsWith('packages/server/')
              ? path.substring('packages/server/'.length)
              : path;
          final listed = source.contains("'$path'") ||
              source.contains("'$serverRelative'");
          expect(
            listed,
            isTrue,
            reason:
                'k5zqAcceptanceTestPaths must list $path (or $serverRelative) '
                'after tentura-u6e lands',
          );
        }
      },
    );
  });
}
