// tentura-pjip: pipeline.yml / pipeline-prod.yml must stay free of
// actionlint's embedded shellcheck findings (SC2086 unquoted variables,
// SC2129 grouped redirects).

import 'dart:io';

import 'package:test/test.dart';

import '../support/github_workflows_actionlint_harness.dart';

void main() {
  late Directory repoRoot;

  setUp(() {
    repoRoot = githubWorkflowsActionlintRepoRootFromServerPackage();
  });

  group('tentura-pjip GitHub workflow actionlint (parent tentura-m0b)', () {
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
