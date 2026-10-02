import 'dart:io';

import 'package:test/test.dart';

import '../packages/server/test/support/ci_web_deploy_verify_harness.dart';

// tentura-6rzi landing gate acceptance (parent tentura-m0b)

/// Same paths as bead tentura-6rzi acceptance harness.
const k6rziAcceptanceTestPaths = [
  'packages/server/test/architecture/tentura_6rzi_ci_web_deploy_verify_test.dart',
  'test/alloy_landing_gate_6rzi_test.dart',
];

const _rzi6LandingGateMarker =
    'tentura-6rzi landing gate acceptance (parent tentura-m0b)';

const _parentBeadMarker = 'parent tentura-m0b';

File _repoFile(String relativePath) => File(relativePath);

Directory _repoRoot() => ciWebDeployVerifyRepoRootFromServerPackage();

void main() {
  group('alloy landing gate (tentura-6rzi / parent tentura-m0b)', () {
    test('6rzi acceptance test files declare 6rzi landing gate markers', () {
      for (final path in k6rziAcceptanceTestPaths) {
        final file = _repoFile(path);
        expect(file.existsSync(), isTrue, reason: 'missing acceptance path $path');
        final source = file.readAsStringSync();
        expect(
          source,
          contains(_rzi6LandingGateMarker),
          reason:
              '$path must tag the 6rzi landing gate for Alloy trial-merge tracking',
        );
        expect(
          source,
          contains(_parentBeadMarker),
          reason: '$path must reference parent bead tentura-m0b',
        );
      }
    });

    test(
      'pipeline.yml post-build verify passes build/web after wasm preload '
      '(tentura-6rzi)',
      () {
        final yaml = readRepoFileForCiWebDeployVerify(
          _repoRoot(),
          k6rziDevPipelineWorkflowRelativePath,
        );
        expectPostBuildVerifyUsesBuildWeb(yaml);
      },
    );

    test(
      'pipeline.yml CI post-build verify shell step rejects stale build/web '
      'from packages/client (tentura-6rzi)',
      () async {
        final repoRoot = _repoRoot();
        final yaml = readRepoFileForCiWebDeployVerify(
          repoRoot,
          k6rziDevPipelineWorkflowRelativePath,
        );
        final verifyShellLine = postBuildVerifyShellLineFromDeployBlock(yaml);
        final clientRoot = Directory('${repoRoot.path}/packages/client');
        await expectCiPostBuildVerifyShellStepRejectsStaleBuildWeb(
          clientPackageRoot: clientRoot,
          verifyShellLine: verifyShellLine,
        );
      },
    );
  });
}
