// tentura-olc landing gate acceptance (trial merge tentura-21x)

import 'dart:io';

import 'package:test/test.dart';

import '../support/server_ci_lint_gate_harness.dart';

/// Alloy tentura-olc landing gate — same paths as the bead acceptance harness.
const kOlcAcceptanceTestPaths = [
  'test/architecture/tentura_olc_landing_check_test.dart',
  'test/architecture/tentura_0cl_agents_olc_fixture_test.dart',
];

const _olcLandingGateMarker =
    'tentura-olc landing gate acceptance (trial merge tentura-21x)';

const _trialMergeMarker = 'trial merge tentura-21x';

const _agentsOlcLandingFixture =
    '../../test/fixtures/agents_alloy_memory_olc_landing_tail.txt';

void main() {
  group('tentura-olc landing check (trial merge tentura-21x)', () {
    test('olc acceptance test paths declare olc landing gate markers', () {
      for (final path in kOlcAcceptanceTestPaths) {
        final file = File(path);
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

    test(
      'bead acceptance: wrapped check-custom-lints.sh packages/server exits 0',
      () {
        final outcome = runOlcAcceptanceServerLintGate();
        expect(
          outcome.exitCode,
          0,
          reason:
              'tentura-olc requires CI-equivalent '
              '`bash scripts/check-custom-lints.sh packages/server` from repo root\n'
              'stdout:\n${outcome.stdout}\n'
              'stderr:\n${outcome.stderr}',
        );
        expect(
          outcome.stdout,
          contains('check-custom-lints: packages/server OK'),
        );
      },
      timeout: const Timeout(Duration(minutes: 12)),
    );

    test(
      'AGENTS.md alloy memory tail records tentura-olc landing gate acceptance',
      () {
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
              'append tentura-olc landing gate acceptance beside jc0 on '
              'alloy/tentura-21x trial merge',
        );
      },
    );
  });
}

File _repoFile(String relativePath) {
  for (final prefix in const ['../../', '']) {
    final candidate = File('$prefix$relativePath');
    if (candidate.existsSync()) {
      return candidate.absolute;
    }
  }
  throw StateError('Repo file not found: $relativePath');
}

