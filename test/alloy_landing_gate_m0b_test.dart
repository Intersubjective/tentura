import 'dart:io';

import 'package:test/test.dart';

import '../packages/server/test/support/github_workflows_actionlint_harness.dart';

// tentura-pjip landing gate acceptance (parent tentura-m0b)

/// Same paths as bead tentura-pjip acceptance harness.
const kPjipAcceptanceTestPaths = [
  'packages/server/test/architecture/tentura_pjip_github_workflows_actionlint_test.dart',
  'test/alloy_landing_gate_m0b_test.dart',
];

const _pjipLandingGateMarker =
    'tentura-pjip landing gate acceptance (parent tentura-m0b)';

const _parentBeadMarker = 'parent tentura-m0b';

File _repoFile(String relativePath) => File(relativePath);

Directory _repoRoot() => Directory('.').absolute;

void main() {
  group('alloy landing gate (tentura-pjip / parent tentura-m0b)', () {
    test('pjip acceptance test files declare pjip landing gate markers', () {
      for (final path in kPjipAcceptanceTestPaths) {
        final file = _repoFile(path);
        expect(file.existsSync(), isTrue, reason: 'missing acceptance path $path');
        final source = file.readAsStringSync();
        expect(
          source,
          contains(_pjipLandingGateMarker),
          reason:
              '$path must tag the pjip landing gate for Alloy trial-merge tracking',
        );
        expect(
          source,
          contains(_parentBeadMarker),
          reason: '$path must reference parent bead tentura-m0b',
        );
      }
    });

    test(
      'docker actionlint exits 0 on pipeline.yml and pipeline-prod.yml with '
      'no SC2086 or SC2129 shellcheck output',
      () async {
        await assertPjipGithubWorkflowsPassActionlint(repoRoot: _repoRoot());
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}
