import 'dart:io';

import 'package:test/test.dart';

// tentura-olc landing gate acceptance (trial merge tentura-21x)

/// Same paths as bead tentura-olc acceptance harness on alloy/tentura-21x.
const kOlcAcceptanceTestPaths = [
  'packages/server/test/architecture/tentura_olc_landing_check_test.dart',
  'packages/server/test/architecture/tentura_0cl_agents_olc_fixture_test.dart',
  'test/alloy_landing_gate_olc_test.dart',
];

const _olcLandingGateMarker =
    'tentura-olc landing gate acceptance (trial merge tentura-21x)';

const _trialMergeMarker = 'trial merge tentura-21x';

const _agentsOlcLandingFixture =
    'test/fixtures/agents_alloy_memory_olc_landing_tail.txt';

File _repoFile(String relativePath) => File(relativePath);

void main() {
  group('alloy landing gate (tentura-olc)', () {
    test('olc acceptance test files declare olc landing gate markers', () {
      for (final path in kOlcAcceptanceTestPaths) {
        final file = _repoFile(path);
        expect(file.existsSync(), isTrue, reason: 'missing acceptance path $path');
        final source = file.readAsStringSync();
        expect(
          source,
          contains(_olcLandingGateMarker),
          reason:
              '$path must tag the olc landing gate for Alloy trial-merge tracking',
        );
        expect(
          source,
          contains(_trialMergeMarker),
          reason: '$path must reference trial merge tentura-21x',
        );
      }
    });

    test('AGENTS.md alloy memory tail matches tentura-olc landing fixture', () {
      final agentsPath = _repoFile('AGENTS.md');
      final fixturePath = _repoFile(_agentsOlcLandingFixture);
      expect(
        fixturePath.existsSync(),
        isTrue,
        reason: 'missing $_agentsOlcLandingFixture',
      );
      final agents = agentsPath.readAsStringSync();
      const beginMarker = '<!-- alloy:memory:begin -->';
      final start = agents.indexOf(beginMarker);
      expect(start, greaterThanOrEqualTo(0), reason: 'missing $beginMarker');
      final actualTail = agents.substring(start).trimRight();
      final expectedTail = fixturePath.readAsStringSync().trimRight();
      expect(
        actualTail,
        equals(expectedTail),
        reason:
            'record tentura-olc landing gate acceptance on alloy/tentura-21x',
      );
    });
  });
}
