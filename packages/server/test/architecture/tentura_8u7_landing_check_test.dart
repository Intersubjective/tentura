// tentura-8u7 landing gate acceptance (parent tentura-8u7)

import 'dart:io';

import 'package:test/test.dart';

import '../support/server_ci_lint_gate_harness.dart';

/// Alloy tentura-8u7 landing gate — the Environment.test DI remediation is
/// tracked through the tentura-pl4 acceptance paths listed here.
const k8u7AcceptanceTestPaths = [
  'test/architecture/tentura_8u7_landing_check_test.dart',
  'test/architecture/tentura_pl4_landing_check_test.dart',
  'test/architecture/tentura_pl4_di_acceptance_probe_test.dart',
  'test/alloy_landing_gate_pl4_test.dart',
];

const _8u7LandingGateMarker =
    'tentura-8u7 landing gate acceptance (parent tentura-8u7)';

void main() {
  group('tentura-8u7 landing check (parent tentura-8u7)', () {
    test('8u7 landing gate file declares the 8u7 landing marker', () {
      final source = File(
        '${serverPackageRoot().path}/'
        'test/architecture/tentura_8u7_landing_check_test.dart',
      ).readAsStringSync();
      expect(
        source,
        contains(_8u7LandingGateMarker),
        reason: 'parent gate must carry the tentura-8u7 landing marker',
      );
    });

    test('8u7 acceptance test paths exist and reference tentura-8u7', () {
      for (final path in k8u7AcceptanceTestPaths) {
        final file = _acceptanceFile(path);
        expect(
          file.existsSync(),
          isTrue,
          reason: 'missing acceptance path $path',
        );
        expect(
          file.readAsStringSync(),
          contains('tentura-8u7'),
          reason: '$path must reference parent landing bead tentura-8u7',
        );
      }
    });
  });
}

File _acceptanceFile(String path) {
  final fromServer = File('${serverPackageRoot().path}/$path');
  if (fromServer.existsSync()) {
    return fromServer;
  }
  return File('${repoRootFromServerPackage().path}/$path');
}
