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
      'web deploy verify extraction is scoped to builder step, not later jobs '
      '(tentura-6rzi fixture)',
      () {
        const fixtureYaml = '''
      - name: Build dev web in builder container
        run: |
          docker run bash -c "
              cd packages/client && flutter gen-l10n
              dart run tool/generate_wasm_preload_artifacts.dart
              dart run tool/verify_web_version_consistency.dart build/web
              cd build/web && tar -czf /app/web-dev.tgz . && cd ../..
            "
      - name: Unrelated later job
        run: |
          docker run bash -c "
              dart run tool/generate_wasm_preload_artifacts.dart
              dart run tool/verify_web_version_consistency.dart build/web
              cd build/web && tar -czf /app/web-decoy.tgz . && cd ../..
            "
''';
        final line = postBuildVerifyShellLineFromDeployBlock(
          fixtureYaml,
          workflowRelativePath: k6rziDevPipelineWorkflowRelativePath,
        );
        expect(line, 'dart run tool/verify_web_version_consistency.dart build/web');
      },
    );

    test(
      'decoy build/web verify before packaging does not satisfy contract when '
      'pre-packaging invoke is no-arg (tentura-6rzi fixture)',
      () {
        const fixtureYaml = '''
      - name: Build dev web in builder container
        run: |
          docker run bash -c "
              cd packages/client && flutter gen-l10n
              dart run tool/generate_wasm_preload_artifacts.dart
              dart run tool/verify_web_version_consistency.dart build/web
              dart run tool/verify_web_version_consistency.dart
              cd build/web && tar -czf /app/web-dev.tgz . && cd ../..
            "
''';
        expect(
          () => expectPostBuildVerifyUsesBuildWeb(
            fixtureYaml,
            workflowRelativePath: k6rziDevPipelineWorkflowRelativePath,
          ),
          throwsA(isA<TestFailure>()),
        );
      },
    );

    test(
      'builder step without docker bash -c cannot borrow a later step verify '
      '(tentura-6rzi fixture)',
      () {
        const fixtureYaml = '''
      - name: Build dev web in builder container
        run: echo missing docker bash
      - name: Unrelated later job
        run: |
          docker run bash -c "
              dart run tool/generate_wasm_preload_artifacts.dart
              dart run tool/verify_web_version_consistency.dart build/web
              cd build/web && tar -czf /app/web-decoy.tgz . && cd ../..
            "
''';
        expect(
          () => postBuildVerifyShellLineFromDeployBlock(
            fixtureYaml,
            workflowRelativePath: k6rziDevPipelineWorkflowRelativePath,
          ),
          throwsA(isA<TestFailure>()),
        );
      },
    );

    test(
      'no-arg post-build verify after wasm preload fails 6rzi contract (fixture)',
      () {
        const brokenWorkflow = '''
      - name: Build dev web in builder container
        run: |
          docker run bash -c "
              cd packages/client && flutter gen-l10n
              dart run tool/trim_web_deploy_artifact.dart
              dart run tool/apply_versioned_web_assets.dart
              dart run tool/generate_wasm_preload_artifacts.dart
              dart run tool/verify_web_version_consistency.dart
              cd build/web && tar -czf /app/web-dev.tgz . && cd ../..
            "
''';
        expect(
          () => expectPostBuildVerifyUsesBuildWeb(
            brokenWorkflow,
            workflowRelativePath: k6rziDevPipelineWorkflowRelativePath,
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
        final line = postBuildVerifyShellLineFromDeployBlock(
          yaml,
          workflowRelativePath: k6rziDevPipelineWorkflowRelativePath,
        );
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
        expectPostBuildVerifyUsesBuildWeb(
          yaml,
          workflowRelativePath: k6rziDevPipelineWorkflowRelativePath,
        );
      },
    );

    test(
      'pipeline.yml web deploy verify rejects stale client build/web only '
      'from workflow shell cwd (tentura-6rzi)',
      () async {
        final repoRoot = _repoRoot();
        final yaml = readRepoFileForCiWebDeployVerify(
          repoRoot,
          k6rziDevPipelineWorkflowRelativePath,
        );
        await expectCiDeployBlockPostBuildVerifyRejectsStaleClientBuildWeb(
          repoRoot: repoRoot,
          workflowYaml: yaml,
          workflowRelativePath: k6rziDevPipelineWorkflowRelativePath,
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
