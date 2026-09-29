import 'dart:io';

import 'package:test/test.dart';

// tentura-5zq landing gate acceptance (parent tentura-617.3)

/// Same paths as bead tentura-5zq acceptance harness.
const k5zqAcceptanceTestPaths = [
  'packages/server/test/architecture/tentura_5zq_server_ci_analyze_gate_test.dart',
  'test/alloy_landing_gate_5zq_test.dart',
];

const _5zqLandingGateMarker =
    'tentura-5zq landing gate acceptance (parent tentura-617.3)';

const _parentBeadMarker = 'parent tentura-617.3';

const _unifiedTailFixture =
    'test/fixtures/agents_alloy_memory_tail_unified_after_5zq.txt';

const _olcLandingTailFixture =
    'test/fixtures/agents_alloy_memory_olc_landing_tail.txt';

const _beginMarker = '<!-- alloy:memory:begin -->';

File _repoFile(String relativePath) => File(relativePath);

String _agentsTailFromMemoryBegin(String agentsText) {
  final start = agentsText.indexOf(_beginMarker);
  expect(start, greaterThanOrEqualTo(0), reason: 'missing $_beginMarker');
  return agentsText.substring(start).trimRight();
}

String _agentsVerifySection(String agentsText) {
  const header = '## Verify';
  final start = agentsText.indexOf(header);
  expect(start, greaterThan(-1), reason: 'AGENTS.md missing ## Verify');
  final nextHeader = agentsText.indexOf('\n## ', start + header.length);
  final end = nextHeader < 0 ? agentsText.length : nextHeader;
  return agentsText.substring(start, end);
}

void main() {
  group('alloy landing gate (tentura-5zq)', () {
    test('5zq acceptance test files declare 5zq landing gate markers', () {
      for (final path in k5zqAcceptanceTestPaths) {
        final file = _repoFile(path);
        expect(file.existsSync(), isTrue, reason: 'missing acceptance path $path');
        final source = file.readAsStringSync();
        expect(
          source,
          contains(_5zqLandingGateMarker),
          reason:
              '$path must tag the 5zq landing gate for Alloy trial-merge tracking',
        );
        expect(
          source,
          contains(_parentBeadMarker),
          reason: '$path must reference parent bead tentura-617.3',
        );
      }
    });

    test(
      'AGENTS.md and olc landing fixtures reconcile after tentura-5zq',
      () {
        final unifiedPath = _repoFile(_unifiedTailFixture);
        final olcFixturePath = _repoFile(_olcLandingTailFixture);
        expect(unifiedPath.existsSync(), isTrue, reason: 'missing $_unifiedTailFixture');
        expect(olcFixturePath.existsSync(), isTrue, reason: 'missing $_olcLandingTailFixture');
        final unified = unifiedPath.readAsStringSync().trimRight();
        final agentsTail = _agentsTailFromMemoryBegin(
          _repoFile('AGENTS.md').readAsStringSync(),
        );
        expect(
          agentsTail,
          equals(unified),
          reason:
              'landing 5zq must update AGENTS.md alloy tail to the unified fixture',
        );
        expect(
          olcFixturePath.readAsStringSync().trimRight(),
          equals(unified),
          reason:
              'landing 5zq must update $_olcLandingTailFixture so '
              'alloy_landing_gate_olc_test.dart and '
              'tentura_olc_landing_check_test.dart stay green',
        );
      },
    );

    test(
      'AGENTS.md Verify documents check-custom-lints.sh for packages/server',
      () {
        final agents = _repoFile('AGENTS.md').readAsStringSync();
        final verify = _agentsVerifySection(agents);
        expect(
          verify,
          contains('check-custom-lints.sh packages/server'),
          reason:
              'AGENTS.md Verify is the agent-facing server lint gate '
              '(tentura-5zq)',
        );
        expect(
          verify,
          isNot(contains('dart analyze .')),
          reason:
              'Verify must not instruct bare fatal-on-warnings '
              '`dart analyze .` for packages/server',
        );
      },
    );
  });
}
