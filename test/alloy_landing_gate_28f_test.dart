import 'dart:io';

import 'package:test/test.dart';

// tentura-28f landing gate acceptance (trial merge tentura-21x)

/// Same paths as bead tentura-28f acceptance on alloy/tentura-21x.
const k28fAcceptanceTestPaths = [
  'packages/server/test/architecture/tentura_28f_landing_check_test.dart',
  'test/alloy_landing_gate_28f_test.dart',
];

const _28fLandingGateMarker =
    'tentura-28f landing gate acceptance (trial merge tentura-21x)';

const _trialMergeMarker = 'trial merge tentura-21x';

const _21xLandingTestRelative =
    'packages/server/test/architecture/tentura_21x_unused_test_setup_test.dart';

File _repoFile(String relativePath) => File(relativePath);

void main() {
  group('alloy landing gate (tentura-28f)', () {
    test('28f acceptance test files declare 28f landing gate markers', () {
      for (final path in k28fAcceptanceTestPaths) {
        final file = _repoFile(path);
        expect(file.existsSync(), isTrue, reason: 'missing acceptance path $path');
        final source = file.readAsStringSync();
        expect(
          source,
          contains(_28fLandingGateMarker),
          reason:
              '$path must tag the 28f landing gate for Alloy trial-merge tracking',
        );
        expect(
          source,
          contains(_trialMergeMarker),
          reason: '$path must reference trial merge tentura-21x',
        );
      }
    });

    test('tentura-21x unused setup landing test ships on trial merge', () {
      final landing = _repoFile(_21xLandingTestRelative);
      expect(
        landing.existsSync(),
        isTrue,
        reason: 'missing $_21xLandingTestRelative',
      );
      expect(
        landing.readAsStringSync(),
        contains('tentura-21x unused test setup'),
        reason: '21x landing gate must guard disposable-PG unused setup',
      );
    });
  });
}
