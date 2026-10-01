// tentura-3zd acceptance: Hasura pg JWT fresh-checkout subprocess harness must
// never rename the real repository `.env` (killed runs must not leave `.env` missing).

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/hasura_pg_jwt_fresh_checkout_harness_contract.dart';

const _3zdAcceptanceMarker = 'tentura-3zd acceptance';

const _harnessRelative = 'test/support/hasura_pg_jwt_keys_test.dart';
const _harnessPartRelative = 'test/support/hasura_pg_jwt_keys_test_3zd.dart';

const _workspaceChildProbeRelative =
    'test/support/hasura_pg_jwt_3zd_workspace_dotenv_child_probe.dart';
const _workspaceChildProbePlainName =
    'tentura-3zd workspace fresh-checkout child dotenv probe';

/// Repo-root Alloy baseline commands (must exit non-zero until tentura-3zd lands).
const kTentura3zdBaselineCommands = <String>[
  './scripts/run_with_test_cleanup.sh --timeout 5m -- bash -lc '
      "'cd packages/server && dart test "
      'test/architecture/tentura_3zd_hasura_pg_jwt_env_harness_test.dart '
      "--tags tentura_3zd_contract'",
  './scripts/run_with_test_cleanup.sh --timeout 5m -- bash -lc '
      "'cd packages/server && dart test "
      'test/architecture/tentura_3zd_hasura_pg_jwt_env_harness_test.dart '
      "--tags tentura_3zd_no_rename'",
  './scripts/run_with_test_cleanup.sh --timeout 5m -- bash -lc '
      "'cd packages/server && dart test "
      'test/architecture/tentura_3zd_hasura_pg_jwt_env_harness_test.dart '
      "--tags tentura_3zd_scratch_isolation'",
  './scripts/run_with_test_cleanup.sh --timeout 5m -- bash -lc '
      "'cd packages/server && dart test "
      'test/architecture/tentura_3zd_hasura_pg_jwt_env_harness_test.dart '
      "--tags tentura_3zd_interrupt'",
];

void main() {
  late final String serverRoot;
  late final String workspaceRepoRoot;
  late final String harnessLibrarySource;

  setUpAll(() {
    serverRoot = _serverPackageRoot();
    workspaceRepoRoot = Directory(serverRoot).parent.parent.absolute.path;
    harnessLibrarySource = _readHarnessLibrarySource();
  });

  tearDown(() async {
    await restoreWorkspaceRepoDotEnvFromHideArtifacts(serverRoot);
  });

  group('tentura-3zd Hasura pg JWT env subprocess harness', () {
    test('acceptance file declares tentura-3zd marker', () {
      final source = File(
        'test/architecture/tentura_3zd_hasura_pg_jwt_env_harness_test.dart',
      ).readAsStringSync();
      expect(
        source,
        contains(_3zdAcceptanceMarker),
        reason: 'Alloy tentura-3zd tracking expects the marker in this file',
      );
    });

    test(
      'fresh-checkout harness keeps workspace .env visible to subprocess child',
      () async {
        final dotEnv = workspaceRepoDotEnvFile(serverRoot);
        if (!dotEnv.existsSync()) {
          markTestSkipped('workspace repo .env required for child visibility probe');
        }

        expect(
          harnessSubprocessEnvIsolatesRepoDotEnv(harnessLibrarySource),
          isTrue,
          reason:
              'harness library must wire dotenv-path env or HOME+scratch copy '
              'without in-place hide (tentura-3zd)',
        );

        final outcome = await runWorkspaceFreshCheckoutHarnessProbe(
          serverPackageRoot: serverRoot,
          workspaceRepoRoot: workspaceRepoRoot,
          probeTestRelative: _workspaceChildProbeRelative,
          probePlainName: _workspaceChildProbePlainName,
        );

        expect(
          outcome.exitCode,
          0,
          reason:
              'workspace .env must still exist when the fresh-checkout child '
              'starts (stdout+stderr:\n${outcome.stdout}\n${outcome.stderr})',
        );
      },
      tags: ['tentura_3zd_contract'],
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'fresh-checkout harness library never hides workspace repo .env in place',
      () {
        final violations = inPlaceRepoDotEnvRenameViolations(harnessLibrarySource);
        expect(
          violations,
          isEmpty,
          reason:
              'rename/hide anywhere in the harness library (including helpers) '
              'can strand workspace .env on SIGKILL (tentura-3zd):\n'
              '${violations.join('\n')}',
        );
      },
      tags: ['tentura_3zd_no_rename'],
    );

    test(
      'fresh-checkout harness copies or redirects dotenv without mutating workspace file',
      () {
        expect(
          inPlaceRepoDotEnvRenameViolations(harnessLibrarySource),
          isEmpty,
          reason: 'scratch copy is meaningless while rename-hide remains',
        );
        expect(
          harnessSubprocessEnvIsolatesRepoDotEnv(harnessLibrarySource),
          isTrue,
          reason:
              'must assign a dotenv-path env var to a scratch file, or set HOME '
              'after copying the workspace .env aside — wired into Process.run '
              'environment (tentura-3zd)',
        );
      },
      tags: ['tentura_3zd_scratch_isolation'],
    );

    test(
      'workspace repo .env survives SIGKILL mid _runFreshCheckoutDartTest',
      () async {
        final dotEnv = workspaceRepoDotEnvFile(serverRoot);
        if (!dotEnv.existsSync()) {
          markTestSkipped('workspace repo .env required for SIGKILL probe');
        }

        final markerDir = await Directory.systemTemp.createTemp(
          'tentura-3zd-sigkill-marker-',
        );
        final readyMarker = File(p.join(markerDir.path, 'ready'));
        addTearDown(() async {
          if (await markerDir.exists()) {
            await markerDir.delete(recursive: true);
          }
        });

        await expectWorkspaceRepoDotEnvSurvivesHarnessSigkill(
          serverPackageRoot: serverRoot,
          workspaceRepoRoot: workspaceRepoRoot,
          readyMarkerFile: readyMarker,
          spawnHarnessRunner: () {
            final repoRoot = p.normalize(p.join(serverRoot, '../..'));
            final wrapper = '$repoRoot/scripts/run_with_test_cleanup.sh';
            return Process.start(
              wrapper,
              [
                '--timeout',
                '2m',
                '--',
                'bash',
                '-lc',
                'cd "$serverRoot" && '
                    'TENTURA_3ZD_WORKSPACE_INTERRUPT_PROBE=1 '
                    'TENTURA_3ZD_SLEEP_PROBE_READY_MARKER="${readyMarker.path}" '
                    'dart test test/support/hasura_pg_jwt_keys_test.dart '
                    '--plain-name "tentura-3zd workspace harness interrupt probe"',
              ],
              workingDirectory: repoRoot,
            );
          },
        );
      },
      tags: ['tentura_3zd_interrupt'],
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('Alloy baseline commands are documented for tentura-3zd', () {
      expect(kTentura3zdBaselineCommands, hasLength(4));
      for (final command in kTentura3zdBaselineCommands) {
        expect(command, startsWith('./scripts/run_with_test_cleanup.sh'));
        expect(command, contains('tentura_3zd_hasura_pg_jwt_env_harness_test.dart'));
      }
    });
  });
}

String _serverPackageRoot() {
  for (final root in const ['.', '../../packages/server']) {
    final dir = Directory(root);
    if (File('${dir.path}/$_harnessRelative').existsSync()) {
      return dir.absolute.path;
    }
  }
  throw StateError('server package root not found for $_harnessRelative');
}

String _readHarnessLibrarySource() {
  final mainSource = _readHarnessSource();
  for (final root in const ['.', '../../packages/server']) {
    final partFile = File('$root/$_harnessPartRelative');
    if (partFile.existsSync()) {
      return '$mainSource\n${partFile.readAsStringSync()}';
    }
  }
  return mainSource;
}

String _readHarnessSource() {
  for (final root in const ['.', '../../packages/server']) {
    final file = File('$root/$_harnessRelative');
    if (file.existsSync()) {
      return file.readAsStringSync();
    }
  }
  throw StateError('$_harnessRelative not found');
}
