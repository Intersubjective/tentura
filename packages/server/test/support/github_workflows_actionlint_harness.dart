import 'dart:io';

import 'package:test/test.dart';

/// tentura-pjip (parent tentura-m0b): actionlint + embedded shellcheck on CI workflows.
const kPjipGithubWorkflowRelativePaths = <String>[
  '.github/workflows/pipeline.yml',
  '.github/workflows/pipeline-prod.yml',
];

const kPjipShellcheckCodes = <String>['SC2086', 'SC2129'];

const kPjipActionlintDockerImage = 'rhysd/actionlint:latest';

/// Flip to `true` only after the committed `.github/workflows/pipeline.yml` and
/// `pipeline-prod.yml` copies pass the bead AC docker actionlint command.
const kPjipWorkflowShellActionlintAcSatisfied = true;

Directory githubWorkflowsActionlintRepoRootFromServerPackage() =>
    Directory('../..').absolute;

Future<bool> isDockerAvailableForActionlint() async {
  try {
    final result = await Process.run('docker', ['info']);
    return result.exitCode == 0;
  } on Object {
    return false;
  }
}

Future<ProcessResult> runGithubWorkflowsActionlintDocker({
  required Directory repoRoot,
}) {
  return Process.run(
    'docker',
    [
      'run',
      '--rm',
      '-v',
      '${repoRoot.path}:/repo',
      '-w',
      '/repo',
      kPjipActionlintDockerImage,
      ...kPjipGithubWorkflowRelativePaths,
    ],
    workingDirectory: repoRoot.path,
  );
}

String combinedProcessOutput(ProcessResult result) =>
    '${result.stdout}\n${result.stderr}';

List<String> pjipShellcheckCodesInActionlintOutput(String combinedOutput) {
  final codes = <String>{};
  final pattern = RegExp(
    r'shellcheck reported issue in this script: (SC\d+):',
  );
  for (final match in pattern.allMatches(combinedOutput)) {
    final code = match.group(1)!;
    if (kPjipShellcheckCodes.contains(code)) {
      codes.add(code);
    }
  }
  return codes.toList()..sort();
}

Future<void> assertPjipGithubWorkflowsPassActionlint({
  required Directory repoRoot,
}) async {
  expect(
    kPjipWorkflowShellActionlintAcSatisfied,
    isTrue,
    reason:
        'tentura-pjip workflow shell remediation is not recorded: set '
        'kPjipWorkflowShellActionlintAcSatisfied to true in '
        'packages/server/test/support/github_workflows_actionlint_harness.dart '
        'only after '
        'docker run --rm -v "\$PWD":/repo -w /repo '
        '$kPjipActionlintDockerImage '
        '${kPjipGithubWorkflowRelativePaths.join(' ')} exits 0 with no '
        'SC2086/SC2129 shellcheck output on the committed workflow copies',
  );

  final dockerOk = await isDockerAvailableForActionlint();
  expect(
    dockerOk,
    isTrue,
    reason:
        'tentura-pjip AC requires Docker to run '
        'docker run --rm -v "\$PWD":/repo -w /repo '
        '$kPjipActionlintDockerImage '
        '${kPjipGithubWorkflowRelativePaths.join(' ')}',
  );

  final result = await runGithubWorkflowsActionlintDocker(repoRoot: repoRoot);
  final combined = combinedProcessOutput(result);

  expect(
    result.exitCode,
    0,
    reason:
        'tentura-pjip AC: '
        'docker run --rm -v "\$PWD":/repo -w /repo '
        '$kPjipActionlintDockerImage '
        '${kPjipGithubWorkflowRelativePaths.join(' ')} must exit 0\n'
        '$combined',
  );

  final defectCodes = pjipShellcheckCodesInActionlintOutput(combined);
  expect(
    defectCodes,
    isEmpty,
    reason:
        'embedded shellcheck must not report SC2086 or SC2129 on the workflow '
        'files (tentura-pjip defect class)\n$combined',
  );
}
