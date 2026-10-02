// tentura-6rzi landing gate acceptance (parent tentura-m0b)

import 'dart:io';

import 'package:test/test.dart';

import '../support/ci_web_deploy_verify_harness.dart';

/// Alloy tentura-6rzi: CI web deploy post-build verify must pass `build/web`.
const k6rziAcceptanceTestPaths = [
  'test/architecture/tentura_6rzi_ci_web_deploy_verify_test.dart',
  '../../test/alloy_landing_gate_6rzi_test.dart',
];

const _rzi6LandingGateMarker =
    'tentura-6rzi landing gate acceptance (parent tentura-m0b)';

const _parentBeadMarker = 'parent tentura-m0b';

Directory _repoRoot() => ciWebDeployVerifyRepoRootFromServerPackage();

void main() {
  group('tentura-6rzi CI web deploy verify (parent tentura-m0b)', () {
    test('6rzi acceptance test paths declare 6rzi landing gate markers', () {
      for (final path in k6rziAcceptanceTestPaths) {
        final file = File(path);
        expect(
          file.existsSync(),
          isTrue,
          reason: 'missing acceptance path $path',
        );
        final source = file.readAsStringSync();
        expect(
          source,
          contains(_rzi6LandingGateMarker),
          reason:
              '$path must tag the 6rzi landing gate for Alloy '
              'trial-merge tracking',
        );
        expect(
          source,
          contains(_parentBeadMarker),
          reason: '$path must reference parent bead tentura-m0b',
        );
      }
    });

    test(
      'supported post-build verify shell parser rejects quoting and extra args '
      '(tentura-6rzi)',
      () {
        expect(
          parseCiPostBuildVerifyShellLine(
            'dart run tool/verify_web_version_consistency.dart',
          ).buildWebPositionalArg,
          isNull,
        );
        expect(
          parseCiPostBuildVerifyShellLine(
            'dart run tool/verify_web_version_consistency.dart build/web',
          ).buildWebPositionalArg,
          'build/web',
        );
        expect(
          () => parseCiPostBuildVerifyShellLine(
            'dart run tool/verify_web_version_consistency.dart "build/web"',
          ),
          throwsA(isA<TestFailure>()),
        );
        expect(
          () => parseCiPostBuildVerifyShellLine(
            'dart run tool/verify_web_version_consistency.dart build/web extra',
          ),
          throwsA(isA<TestFailure>()),
        );
      },
    );

    test(
      'pipeline.yml post-build verify uses supported CI shell syntax only '
      '(tentura-6rzi)',
      () {
        final yaml = readRepoFileForCiWebDeployVerify(
          _repoRoot(),
          k6rziDevPipelineWorkflowRelativePath,
        );
        final line = postBuildVerifyShellLineFromDeployBlock(yaml);
        expect(
          () => parseCiPostBuildVerifyShellLine(line),
          returnsNormally,
          reason:
              'dev deploy block must use supported verify shell syntax '
              '(no-arg or single build/web positional, '
              'no quoting/continuations)',
        );
      },
    );

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

    test(
      'tentura-m0b verify_web_version_consistency regression stays green '
      '(tentura-6rzi existing suite AC)',
      () async {
        await assertM0bVerifyToolRegressionTestsGreen(repoRoot: _repoRoot());
      },
      timeout: const Timeout(Duration(minutes: 6)),
    );
  });
}
