// CI web deploy's post-build verify step must pass `build/web`, so the deploy
// artifact's own version consistency keeps being checked (the no-arg default
// checks tracked sources, so a caller relying on no-arg to check the built
// artifact would otherwise silently stop doing so).

import 'dart:io';

import 'package:test/test.dart';

import '../support/ci_web_deploy_verify_harness.dart';

Directory _repoRoot() => ciWebDeployVerifyRepoRootFromServerPackage();

void main() {
  group('CI web deploy verify', () {
    test(
      'supported post-build verify shell parser rejects quoting and extra args',
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
      'web deploy verify extraction is scoped to builder step, not later jobs',
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
          workflowRelativePath: kDevPipelineWorkflowRelativePath,
        );
        expect(
          line,
          'dart run tool/verify_web_version_consistency.dart build/web',
        );
      },
    );

    test(
      'decoy build/web verify before packaging does not satisfy contract when '
      'pre-packaging invoke is no-arg',
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
            workflowRelativePath: kDevPipelineWorkflowRelativePath,
          ),
          throwsA(isA<TestFailure>()),
        );
      },
    );

    test(
      'builder step without docker bash -c cannot borrow a later step verify',
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
            workflowRelativePath: kDevPipelineWorkflowRelativePath,
          ),
          throwsA(isA<TestFailure>()),
        );
      },
    );

    test(
      'no-arg post-build verify after wasm preload fails the contract',
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
            workflowRelativePath: kDevPipelineWorkflowRelativePath,
          ),
          throwsA(isA<TestFailure>()),
        );
      },
    );

    test(
      'pipeline.yml post-build verify uses supported CI shell syntax only',
      () {
        final yaml = readRepoFileForCiWebDeployVerify(
          _repoRoot(),
          kDevPipelineWorkflowRelativePath,
        );
        final line = postBuildVerifyShellLineFromDeployBlock(
          yaml,
          workflowRelativePath: kDevPipelineWorkflowRelativePath,
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
      'pipeline.yml post-build verify passes build/web after wasm preload',
      () {
        final yaml = readRepoFileForCiWebDeployVerify(
          _repoRoot(),
          kDevPipelineWorkflowRelativePath,
        );
        expectPostBuildVerifyUsesBuildWeb(
          yaml,
          workflowRelativePath: kDevPipelineWorkflowRelativePath,
        );
      },
    );
  });
}
