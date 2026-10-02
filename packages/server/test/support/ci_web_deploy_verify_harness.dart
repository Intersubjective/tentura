import 'dart:io';

import 'package:test/test.dart';

/// CI web deploy post-build verify.
const kDevPipelineWorkflowRelativePath = '.github/workflows/pipeline.yml';

const kDevWebDeployBuilderStepName = 'Build dev web in builder container';

final _gitHubWorkflowSiblingStepHeader = RegExp(r'\n      - name: ');

const _postBuildVerifyNoArgShellLine =
    'dart run tool/verify_web_version_consistency.dart';

const _postBuildVerifyBuildWebShellLine =
    'dart run tool/verify_web_version_consistency.dart build/web';

final _supportedNoArgVerifyShellLine = RegExp(
  r'^dart run tool/verify_web_version_consistency\.dart$',
);

final _supportedBuildWebVerifyShellLine = RegExp(
  r'^dart run tool/verify_web_version_consistency\.dart build/web$',
);

final _postBuildVerifyShellLinePattern = RegExp(
  r'^[ \t]*dart run tool/verify_web_version_consistency\.dart(?: build/web)?',
  multiLine: true,
);

Directory ciWebDeployVerifyRepoRootFromServerPackage() {
  for (final start in [
    Directory.current,
    Directory('../..'),
    Directory('../../..'),
  ]) {
    final script = File('${start.path}/scripts/run_with_test_cleanup.sh');
    if (script.existsSync()) {
      return start.absolute;
    }
  }
  throw StateError('repo root not found');
}

String readRepoFileForCiWebDeployVerify(
  Directory repoRoot,
  String relativePath,
) {
  final file = File('${repoRoot.path}/$relativePath');
  if (!file.existsSync()) {
    throw StateError('repo file not found: ${file.path}');
  }
  return file.readAsStringSync();
}

void _expectDevPipelineWorkflow(String workflowRelativePath) {
  expect(
    workflowRelativePath,
    kDevPipelineWorkflowRelativePath,
    reason:
        'this check applies only to '
        '$kDevPipelineWorkflowRelativePath',
  );
}

/// YAML for one workflow step, from its `- name:` through the next sibling step.
String extractGitHubWorkflowStepYamlBlock(
  String workflowYaml, {
  required String stepName,
  required String workflowRelativePath,
}) {
  final stepHeader = RegExp(
    '^      - name: ${RegExp.escape(stepName)}\$',
    multiLine: true,
  );
  final stepMatch = stepHeader.firstMatch(workflowYaml);
  expect(
    stepMatch,
    isNotNull,
    reason: '$workflowRelativePath must declare workflow step "$stepName"',
  );
  final afterHeader = workflowYaml.substring(stepMatch!.end);
  final nextStep = _gitHubWorkflowSiblingStepHeader.firstMatch(afterHeader);
  final stepEnd = nextStep == null
      ? workflowYaml.length
      : stepMatch.end + nextStep.start;
  return workflowYaml.substring(stepMatch.start, stepEnd);
}

/// Inner `bash -c "…"` script from the dev builder-container web deploy step.
String extractWebDeployDockerBashScript(
  String workflowYaml, {
  required String workflowRelativePath,
}) {
  _expectDevPipelineWorkflow(workflowRelativePath);
  final stepYaml = extractGitHubWorkflowStepYamlBlock(
    workflowYaml,
    stepName: kDevWebDeployBuilderStepName,
    workflowRelativePath: workflowRelativePath,
  );
  const bashOpen = 'bash -c "';
  final bashStart = stepYaml.indexOf(bashOpen);
  expect(
    bashStart,
    greaterThan(-1),
    reason:
        '$workflowRelativePath "$kDevWebDeployBuilderStepName" step must '
        'run post-build tools via docker bash -c (not a later workflow step)',
  );
  final scriptStart = bashStart + bashOpen.length;
  final scriptEnd = stepYaml.lastIndexOf('\n            "');
  expect(
    scriptEnd,
    greaterThan(scriptStart),
    reason:
        '$workflowRelativePath "$kDevWebDeployBuilderStepName" docker '
        'bash -c script must close inside that step',
  );
  return stepYaml.substring(scriptStart, scriptEnd);
}

RegExpMatch _prePackagingVerifyLineMatch(
  String innerShellScript, {
  required String workflowRelativePath,
}) {
  const wasmMarker = 'dart run tool/generate_wasm_preload_artifacts.dart';
  const packageTarMarker = 'cd build/web && tar';

  final wasmIndex = innerShellScript.indexOf(wasmMarker);
  expect(
    wasmIndex,
    greaterThan(-1),
    reason:
        '$workflowRelativePath web deploy docker script must run '
        '$wasmMarker before pre-packaging verify',
  );

  final tarIndex = innerShellScript.indexOf(packageTarMarker);
  expect(
    tarIndex,
    greaterThan(wasmIndex),
    reason:
        '$workflowRelativePath must package build/web immediately after '
        'post-build verify',
  );

  final beforeTar = innerShellScript.substring(0, tarIndex);
  final matches = _postBuildVerifyShellLinePattern
      .allMatches(beforeTar)
      .toList();
  expect(
    matches,
    isNotEmpty,
    reason:
        '$workflowRelativePath web deploy docker script must invoke '
        'verify_web_version_consistency immediately before packaging',
  );

  final verifyMatch = matches.last;
  final betweenLastVerifyAndTar = beforeTar.substring(verifyMatch.end);
  expect(
    _postBuildVerifyShellLinePattern.hasMatch(betweenLastVerifyAndTar),
    isFalse,
    reason:
        '$workflowRelativePath must not treat an earlier decoy verify command '
        'as the deploy guard; only the invocation before cd build/web counts',
  );

  return verifyMatch;
}

String postBuildVerifyShellLineFromWebDeployInnerShell(
  String innerShellScript, {
  required String workflowRelativePath,
}) {
  return _prePackagingVerifyLineMatch(
    innerShellScript,
    workflowRelativePath: workflowRelativePath,
  ).group(0)!.trim();
}

String postBuildVerifyShellLineFromDeployBlock(
  String workflowYaml, {
  String workflowRelativePath = kDevPipelineWorkflowRelativePath,
}) {
  final innerShell = extractWebDeployDockerBashScript(
    workflowYaml,
    workflowRelativePath: workflowRelativePath,
  );
  return postBuildVerifyShellLineFromWebDeployInnerShell(
    innerShell,
    workflowRelativePath: workflowRelativePath,
  );
}

/// Supported CI syntax: no-arg or single unquoted `build/web` positional only.
CiPostBuildVerifyShellInvocation parseCiPostBuildVerifyShellLine(
  String verifyShellLine,
) {
  final trimmed = verifyShellLine.trim();
  if (_supportedNoArgVerifyShellLine.hasMatch(trimmed)) {
    return CiPostBuildVerifyShellInvocation(
      shellLine: trimmed,
      buildWebPositionalArg: null,
    );
  }
  if (_supportedBuildWebVerifyShellLine.hasMatch(trimmed)) {
    return CiPostBuildVerifyShellInvocation(
      shellLine: trimmed,
      buildWebPositionalArg: 'build/web',
    );
  }
  throw TestFailure(
    'unsupported post-build verify shell line in '
    '$kDevPipelineWorkflowRelativePath: "$trimmed" — '
    'only "$_postBuildVerifyNoArgShellLine" or '
    '"$_postBuildVerifyBuildWebShellLine" are supported',
  );
}

final class CiPostBuildVerifyShellInvocation {
  const CiPostBuildVerifyShellInvocation({
    required this.shellLine,
    required this.buildWebPositionalArg,
  });

  final String shellLine;
  final String? buildWebPositionalArg;
}

void expectWebDeployInnerShellVerifyRunsFromClientPackage({
  required String innerShellScript,
  required String workflowRelativePath,
}) {
  const cdClientMarker = 'cd packages/client';

  final verifyMatch = _prePackagingVerifyLineMatch(
    innerShellScript,
    workflowRelativePath: workflowRelativePath,
  );
  final verifyIndex = verifyMatch.start;

  final cdClientIndex = innerShellScript.lastIndexOf(
    cdClientMarker,
    verifyIndex,
  );
  expect(
    cdClientIndex,
    greaterThan(-1),
    reason:
        '$workflowRelativePath must cd packages/client before post-build '
        'verify so build/web resolves to the finished client artifact',
  );

  final betweenClientCdAndVerify = innerShellScript.substring(
    cdClientIndex,
    verifyIndex,
  );
  expect(
    betweenClientCdAndVerify,
    isNot(contains('cd ..')),
    reason:
        '$workflowRelativePath must not leave packages/client before verify',
  );
  expect(
    betweenClientCdAndVerify,
    isNot(contains('cd /app')),
    reason: '$workflowRelativePath must not return to /app before verify',
  );

  final tarIndex = innerShellScript.indexOf('cd build/web', verifyIndex);
  expect(
    tarIndex,
    greaterThan(verifyIndex),
    reason:
        '$workflowRelativePath must verify build/web before cd build/web '
        'packaging',
  );
}

void expectPostBuildVerifyUsesBuildWeb(
  String workflowYaml, {
  required String workflowRelativePath,
}) {
  final innerShell = extractWebDeployDockerBashScript(
    workflowYaml,
    workflowRelativePath: workflowRelativePath,
  );
  expectWebDeployInnerShellVerifyRunsFromClientPackage(
    innerShellScript: innerShell,
    workflowRelativePath: workflowRelativePath,
  );
  final parsed = parseCiPostBuildVerifyShellLine(
    postBuildVerifyShellLineFromWebDeployInnerShell(
      innerShell,
      workflowRelativePath: workflowRelativePath,
    ),
  );
  expect(
    parsed.shellLine,
    _postBuildVerifyBuildWebShellLine,
    reason:
        '$workflowRelativePath must pass build/web after '
        'generate_wasm_preload_artifacts so post-build artifact consistency '
        'is checked (no-arg verify is source-only)',
  );
}
