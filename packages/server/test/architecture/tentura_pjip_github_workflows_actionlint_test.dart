// tentura-pjip landing gate acceptance (parent tentura-m0b)

import 'dart:io';

import 'package:test/test.dart';

import '../support/github_workflows_actionlint_harness.dart';

const _pjipLandingGateMarker =
    'tentura-pjip landing gate acceptance (parent tentura-m0b)';

void main() {
  late Directory repoRoot;

  setUp(() {
    repoRoot = githubWorkflowsActionlintRepoRootFromServerPackage();
  });

  group('tentura-pjip GitHub workflow actionlint (parent tentura-m0b)', () {
    test('acceptance file declares pjip landing gate marker', () {
      expect(
        File(
          'test/architecture/tentura_pjip_github_workflows_actionlint_test.dart',
        ).readAsStringSync(),
        contains(_pjipLandingGateMarker),
      );
    });

    test(
      'docker actionlint exits 0 on pipeline.yml and pipeline-prod.yml with '
      'no SC2086 or SC2129 shellcheck output',
      () async {
        await assertPjipGithubWorkflowsPassActionlint(repoRoot: repoRoot);
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}
