import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// tentura-6rzi (parent tentura-m0b): dev CI web deploy post-build verify.
const k6rziDevPipelineWorkflowRelativePath = '.github/workflows/pipeline.yml';

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

/// Dev web deploy bash script tail after wasm preload (builder step).
String devWebDeployPostBuildShellTail(String workflowYaml) {
  const marker = 'dart run tool/generate_wasm_preload_artifacts.dart';
  final markerIndex = workflowYaml.lastIndexOf(marker);
  expect(
    markerIndex,
    greaterThan(-1),
    reason:
        '$k6rziDevPipelineWorkflowRelativePath must run '
        'generate_wasm_preload_artifacts.dart in the dev web deploy block',
  );
  return workflowYaml.substring(markerIndex);
}

String postBuildVerifyShellLineFromDeployBlock(String workflowYaml) {
  final tail = devWebDeployPostBuildShellTail(workflowYaml);
  final match = RegExp(
    r'^[ \t]*dart run tool/verify_web_version_consistency\.dart(?: build/web)?',
    multiLine: true,
  ).firstMatch(tail);
  expect(
    match,
    isNotNull,
    reason:
        'dev web deploy block in $k6rziDevPipelineWorkflowRelativePath must '
        'invoke verify_web_version_consistency after wasm preload',
  );
  return match!.group(0)!.trim();
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

void expectPostBuildVerifyUsesBuildWeb(String workflowYaml) {
  final parsed = parseCiPostBuildVerifyShellLine(
    postBuildVerifyShellLineFromDeployBlock(workflowYaml),
  );
  expect(
    parsed.shellLine,
    _postBuildVerifyBuildWebShellLine,
    reason:
        '$k6rziDevPipelineWorkflowRelativePath must pass build/web after '
        'generate_wasm_preload_artifacts so post-build artifact consistency '
        'is checked (tentura-6rzi; no-arg verify is source-only after '
        'tentura-m0b)',
  );
}

Future<ProcessResult> runCiPostBuildVerifyShellStep({
  required Directory clientPackageRoot,
  required String verifyShellLine,
}) {
  return Process.run(
    'bash',
    ['-eu', '-c', verifyShellLine.trim()],
    workingDirectory: clientPackageRoot.path,
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
    clientPackageRoot: clientPackageRoot,
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
    if (buildWebDir.existsSync()) {
      for (final entry in buildWebDir.listSync(followLinks: false)) {
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
}) async {
  final yaml = readRepoFileForCiWebDeployVerify(
    repoRoot,
    k6rziDevPipelineWorkflowRelativePath,
  );
  expectPostBuildVerifyUsesBuildWeb(yaml);
  final verifyShellLine = postBuildVerifyShellLineFromDeployBlock(yaml);

  final clientRoot = Directory('${repoRoot.path}/packages/client');
  expect(
    File('${clientRoot.path}/tool/verify_web_version_consistency.dart')
        .existsSync(),
    isTrue,
  );
  await expectCiPostBuildVerifyShellStepRejectsStaleBuildWeb(
    clientPackageRoot: clientRoot,
    verifyShellLine: verifyShellLine,
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
