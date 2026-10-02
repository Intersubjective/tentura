import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// tentura-6rzi (parent tentura-m0b): CI web deploy post-build verify.
const k6rziDevPipelineWorkflowRelativePath = '.github/workflows/pipeline.yml';

const k6rziDevWebDeployBuilderStepName = 'Build dev web in builder container';

final _gitHubWorkflowSiblingStepHeader = RegExp(r'\n      - name: ');

const k6rziM0bVerifyToolRegressionRelativePath =
    'packages/client/test/tool/verify_web_version_consistency_test.dart';

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

void _expect6rziDevPipelineWorkflow(String workflowRelativePath) {
  expect(
    workflowRelativePath,
    k6rziDevPipelineWorkflowRelativePath,
    reason:
        'tentura-6rzi acceptance applies only to '
        '$k6rziDevPipelineWorkflowRelativePath',
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
    reason:
        '$workflowRelativePath must declare workflow step "$stepName"',
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
  _expect6rziDevPipelineWorkflow(workflowRelativePath);
  final stepYaml = extractGitHubWorkflowStepYamlBlock(
    workflowYaml,
    stepName: k6rziDevWebDeployBuilderStepName,
    workflowRelativePath: workflowRelativePath,
  );
  const bashOpen = 'bash -c "';
  final bashStart = stepYaml.indexOf(bashOpen);
  expect(
    bashStart,
    greaterThan(-1),
    reason:
        '$workflowRelativePath "$k6rziDevWebDeployBuilderStepName" step must '
        'run post-build tools via docker bash -c (not a later workflow step)',
  );
  final scriptStart = bashStart + bashOpen.length;
  final scriptEnd = stepYaml.lastIndexOf('\n            "');
  expect(
    scriptEnd,
    greaterThan(scriptStart),
    reason:
        '$workflowRelativePath "$k6rziDevWebDeployBuilderStepName" docker '
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
  final matches = _postBuildVerifyShellLinePattern.allMatches(beforeTar).toList();
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
  String workflowRelativePath = k6rziDevPipelineWorkflowRelativePath,
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
    '$k6rziDevPipelineWorkflowRelativePath (tentura-6rzi): "$trimmed" — '
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

  final cdClientIndex = innerShellScript.lastIndexOf(cdClientMarker, verifyIndex);
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
    reason:
        '$workflowRelativePath must not return to /app before verify',
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
        'is checked (tentura-6rzi; no-arg verify is source-only after '
        'tentura-m0b)',
  );
}

Future<ProcessResult> runCiPostBuildVerifyShellStep({
  required Directory workingDirectory,
  required String verifyShellLine,
}) {
  return Process.run(
    'bash',
    ['-eu', '-c', verifyShellLine.trim()],
    workingDirectory: workingDirectory.path,
    environment: {
      ...Platform.environment,
      'WEB_BUILD_ID': '',
    },
  );
}

void _writeStaleBuildWebForVerifyHarness({
  required Directory buildWebDir,
  required String staleVersion,
}) {
  buildWebDir.createSync(recursive: true);
  File('${buildWebDir.path}/index.html').writeAsStringSync(
    '<script src="flutter_bootstrap.js?v=$staleVersion"></script>',
  );
  File('${buildWebDir.path}/manifest.json').writeAsStringSync(
    jsonEncode({'version': staleVersion}),
  );
  File('${buildWebDir.path}/flutter_bootstrap.js').writeAsStringSync('');
  File('${buildWebDir.path}/wasm-preload-manifest.json').writeAsStringSync(
    jsonEncode({
      'version': staleVersion,
      'sharedPreload': ['/flutter_bootstrap.js?v=$staleVersion'],
      'wasmPreload': <String>[],
      'jsPreload': <String>[],
    }),
  );
  File('${buildWebDir.path}/tentura-app-cache-sw.js').writeAsStringSync(
    "const CACHE_VERSION = '$staleVersion';",
  );
}

void _writeConsistentBuildWebForVerifyHarness({
  required Directory buildWebDir,
  required String version,
}) {
  buildWebDir.createSync(recursive: true);
  File('${buildWebDir.path}/index.html').writeAsStringSync(
    '<script src="flutter_bootstrap.js?v=$version"></script>',
  );
  File('${buildWebDir.path}/manifest.json').writeAsStringSync(
    jsonEncode({'version': version}),
  );
  File('${buildWebDir.path}/flutter_bootstrap.js').writeAsStringSync('');
  File('${buildWebDir.path}/main.dart.js').writeAsStringSync('');
  File('${buildWebDir.path}/main.dart.wasm').writeAsStringSync('');
  File('${buildWebDir.path}/wasm-preload-manifest.json').writeAsStringSync(
    jsonEncode({
      'version': version,
      'sharedPreload': ['/flutter_bootstrap.js?v=$version'],
      'wasmPreload': <String>['/main.dart.wasm'],
      'jsPreload': <String>['/main.dart.js'],
    }),
  );
  File('${buildWebDir.path}/tentura-app-cache-sw.js').writeAsStringSync(
    "const CACHE_VERSION = '$version';",
  );
}

Future<void> expectCiDeployBlockPostBuildVerifyRejectsStaleClientBuildWeb({
  required Directory repoRoot,
  required String workflowYaml,
  required String workflowRelativePath,
}) async {
  final innerShell = extractWebDeployDockerBashScript(
    workflowYaml,
    workflowRelativePath: workflowRelativePath,
  );
  expectWebDeployInnerShellVerifyRunsFromClientPackage(
    innerShellScript: innerShell,
    workflowRelativePath: workflowRelativePath,
  );
  final verifyShellLine = postBuildVerifyShellLineFromWebDeployInnerShell(
    innerShell,
    workflowRelativePath: workflowRelativePath,
  );
  final parsed = parseCiPostBuildVerifyShellLine(verifyShellLine);
  expect(
    parsed.buildWebPositionalArg,
    'build/web',
    reason:
        'deploy-time stale-artifact guard requires build/web verify in '
        '$workflowRelativePath',
  );

  const staleVersion = '0.0.0-stale-ci-deploy-artifacts';
  final clientRoot = Directory('${repoRoot.path}/packages/client');
  final clientBuildWeb = Directory('${clientRoot.path}/build/web');
  final repoBuildWeb = Directory('${repoRoot.path}/build/web');

  final clientBackedUp = <String, List<int>?>{};
  if (clientBuildWeb.existsSync()) {
    for (final entry in clientBuildWeb.listSync(followLinks: false)) {
      if (entry is File) {
        clientBackedUp[entry.path] = entry.readAsBytesSync();
      }
    }
  }
  final repoBackedUp = <String, List<int>?>{};
  if (repoBuildWeb.existsSync()) {
    for (final entry in repoBuildWeb.listSync(followLinks: false)) {
      if (entry is File) {
        repoBackedUp[entry.path] = entry.readAsBytesSync();
      }
    }
  }

  _writeStaleBuildWebForVerifyHarness(
    buildWebDir: clientBuildWeb,
    staleVersion: staleVersion,
  );

  final pubspecVersion = RegExp(
    r'^version:\s*([^\s+]+)',
    multiLine: true,
  ).firstMatch(File('${clientRoot.path}/pubspec.yaml').readAsStringSync());
  expect(pubspecVersion, isNotNull);
  final consistentVersion = pubspecVersion!.group(1)!;
  _writeConsistentBuildWebForVerifyHarness(
    buildWebDir: repoBuildWeb,
    version: consistentVersion,
  );

  try {
    final wrongCwdResult = await runCiPostBuildVerifyShellStep(
      workingDirectory: repoRoot,
      verifyShellLine: parsed.shellLine,
    );
    expect(
      wrongCwdResult.exitCode,
      isNot(0),
      reason:
          'workflow-relative verify (${parsed.shellLine}) must not succeed '
          'from repo root; deploy guard requires packages/client cwd '
          '(stale client build/web must not be hidden by a decoy repo '
          'build/web)\nstdout: ${wrongCwdResult.stdout}\n'
          'stderr: ${wrongCwdResult.stderr}',
    );

    final decoyOnlyResult = await Process.run(
      'dart',
      [
        'run',
        'tool/verify_web_version_consistency.dart',
        '../../build/web',
      ],
      workingDirectory: clientRoot.path,
      environment: {
        ...Platform.environment,
        'WEB_BUILD_ID': '',
      },
    );
    expect(
      decoyOnlyResult.exitCode,
      0,
      reason:
          'consistent decoy build/web at repo root must pass verify when '
          'packages/client/build/web is stale (proves cwd-relative build/web '
          'path)\nstdout: ${decoyOnlyResult.stdout}\n'
          'stderr: ${decoyOnlyResult.stderr}',
    );

    final workflowCwdResult = await runCiPostBuildVerifyShellStep(
      workingDirectory: clientRoot,
      verifyShellLine: parsed.shellLine,
    );
    expect(
      workflowCwdResult.exitCode,
      isNot(0),
      reason:
          'web deploy verify (${parsed.shellLine}) must reject stale '
          'packages/client/build/web when run from the workflow shell cwd\n'
          'stdout: ${workflowCwdResult.stdout}\n'
          'stderr: ${workflowCwdResult.stderr}',
    );
  } finally {
    _restoreBackedUpFiles(clientBuildWeb, clientBackedUp);
    _restoreBackedUpFiles(repoBuildWeb, repoBackedUp);
  }
}

void _restoreBackedUpFiles(
  Directory dir,
  Map<String, List<int>?> backedUp,
) {
  if (!dir.existsSync()) {
    return;
  }
  for (final entry in dir.listSync(followLinks: false)) {
    if (entry is File) {
      final bytes = backedUp[entry.path];
      if (bytes == null) {
        entry.deleteSync();
      } else {
        entry.writeAsBytesSync(bytes);
      }
    }
  }
}

Future<void> expectCiPostBuildVerifyShellStepRejectsStaleBuildWeb({
  required Directory clientPackageRoot,
  required String verifyShellLine,
}) async {
  const staleVersion = '0.0.0-stale-ci-deploy-artifacts';
  final buildWebDir = Directory('${clientPackageRoot.path}/build/web');
  final backedUp = <String, List<int>?>{};
  if (buildWebDir.existsSync()) {
    for (final entry in buildWebDir.listSync(followLinks: false)) {
      if (entry is File) {
        backedUp[entry.path] = entry.readAsBytesSync();
      }
    }
  }
  _writeStaleBuildWebForVerifyHarness(
    buildWebDir: buildWebDir,
    staleVersion: staleVersion,
  );

  final parsed = parseCiPostBuildVerifyShellLine(verifyShellLine);
  final result = await runCiPostBuildVerifyShellStep(
    workingDirectory: clientPackageRoot,
    verifyShellLine: parsed.shellLine,
  );

  try {
    expect(
      result.exitCode,
      isNot(0),
      reason:
          'CI post-build shell step (${parsed.shellLine}) must reject stale '
          'build/web deploy artifacts after generate_wasm_preload_artifacts '
          'when run from packages/client with set -e; no-arg verify only '
          'checks tracked sources after tentura-m0b (tentura-6rzi)\n'
          'stdout: ${result.stdout}\nstderr: ${result.stderr}',
    );
  } finally {
    _restoreBackedUpFiles(buildWebDir, backedUp);
  }
}

Future<void> assertM0bVerifyToolRegressionTestsGreen({
  required Directory repoRoot,
}) async {
  final regressionTest = File(
    '${repoRoot.path}/$k6rziM0bVerifyToolRegressionRelativePath',
  );
  expect(
    regressionTest.existsSync(),
    isTrue,
    reason: 'missing $k6rziM0bVerifyToolRegressionRelativePath',
  );
  final wrapper = File('${repoRoot.path}/scripts/run_with_test_cleanup.sh');
  expect(wrapper.existsSync(), isTrue);
  final result = await Process.run(
    wrapper.path,
    [
      '--timeout',
      '5m',
      '--',
      'flutter',
      'test',
      'test/tool/verify_web_version_consistency_test.dart',
      '--dart-define=ENV=test',
    ],
    workingDirectory: '${repoRoot.path}/packages/client',
  );
  expect(
    result.exitCode,
    0,
    reason:
        'tentura-m0b verify_web_version_consistency tests must stay green while '
        '6rzi fixes CI deploy verify (tentura-6rzi AC: existing suite)\n'
        'stdout: ${result.stdout}\nstderr: ${result.stderr}',
  );
}

Future<void> assert6rziCiWebDeployVerifyContract({
  required Directory repoRoot,
  required String workflowRelativePath,
}) async {
  final yaml = readRepoFileForCiWebDeployVerify(repoRoot, workflowRelativePath);
  expectPostBuildVerifyUsesBuildWeb(
    yaml,
    workflowRelativePath: workflowRelativePath,
  );
  await expectCiDeployBlockPostBuildVerifyRejectsStaleClientBuildWeb(
    repoRoot: repoRoot,
    workflowYaml: yaml,
    workflowRelativePath: workflowRelativePath,
  );
}

// Legacy names used by landing-gate tests.
String postBuildVerifyInvocationLine(String workflowYaml) =>
    postBuildVerifyShellLineFromDeployBlock(workflowYaml);

Future<void> expectCiExtractedPostBuildVerifyRejectsStaleBuildWeb({
  required Directory clientPackageRoot,
  required String verifyInvocationLine,
}) =>
    expectCiPostBuildVerifyShellStepRejectsStaleBuildWeb(
      clientPackageRoot: clientPackageRoot,
      verifyShellLine: verifyInvocationLine,
    );
