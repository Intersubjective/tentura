// tentura-u6e landing gate acceptance (fix tentura-5zq)

import 'dart:io';

import 'package:test/test.dart';

import '../support/server_ci_lint_gate_harness.dart';

/// Alloy tentura-u6e — same paths as bead acceptance harness.
const kU6eAcceptanceTestPaths = [
  'test/architecture/tentura_u6e_landing_check_test.dart',
  'test/alloy_landing_gate_u6e_test.dart',
];

const _u6eLandingGateMarker =
    'tentura-u6e landing gate acceptance (fix tentura-5zq)';

const _5zqLandingCheckRelative =
    'test/architecture/tentura_5zq_server_ci_analyze_gate_test.dart';

Object get _skipNestedCleanupInCiDartTest {
  final env = Platform.environment;
  if (env['GITHUB_ACTIONS'] == 'true' ||
      env['CI'] == 'true' ||
      env['TEST_TARGET'] == 'server' ||
      env['TENTURA_U6E_NESTED_SUITE'] == 'true') {
      return 'do not recursively nest run_with_test_cleanup.sh';
  }
  return false;
}

void main() {
  group('tentura-u6e landing check (fix tentura-5zq)', () {
    test('u6e acceptance test paths declare u6e landing gate markers', () {
      for (final path in kU6eAcceptanceTestPaths) {
        final file = _resolveRepoRelative(path);
        expect(file.existsSync(), isTrue, reason: 'missing acceptance path $path');
        final source = file.readAsStringSync();
        expect(
          source,
          contains(_u6eLandingGateMarker),
          reason:
              '$path must tag the u6e landing gate for Alloy trial-merge tracking',
        );
        expect(
          source,
          contains('fix tentura-5zq'),
          reason: '$path must reference parent landing bead tentura-5zq',
        );
      }
    });

    test(
      'tentura-5zq landing gate lists u6e acceptance paths for non-pg suite remediation',
      () {
        final source = File(
          '${serverPackageRoot().path}/$_5zqLandingCheckRelative',
        ).readAsStringSync();
        for (final path in kU6eAcceptanceTestPaths) {
          if (path.startsWith('test/alloy_landing_gate')) {
            continue;
          }
          expect(
            source,
            contains("'$path'"),
            reason:
                '$_5zqLandingCheckRelative k5zqAcceptanceTestPaths must include '
                '$path so Alloy tentura-5zq landing tracks u6e (tentura-u6e)',
          );
        }
      },
    );

    test(
      'bead acceptance: wrapped dart test --exclude-tags pg exits 0 (tentura-5zq landing)',
      () {
        final outcome = runU6eAcceptanceNonPgDartTest();
        expect(
          outcome.exitCode,
          0,
          reason:
              'tentura-u6e requires '
              '`cd packages/server && '
              '../../scripts/run_with_test_cleanup.sh --timeout 20m -- '
              'dart test --exclude-tags pg` '
              'to exit 0 on alloy/tentura-5zq trial merge\n'
              'stdout:\n${outcome.stdout}\n'
              'stderr:\n${outcome.stderr}',
        );
      },
      timeout: const Timeout(Duration(minutes: 21)),
      skip: _skipNestedCleanupInCiDartTest,
    );

    test(
      'AGENTS.md records tentura-u6e landing gate acceptance beside tentura-5zq',
      () {
        final agents = _repoFile('AGENTS.md').readAsStringSync();
        expect(
          agents,
          contains('<!-- tentura-u6e landing gate acceptance (fix tentura-5zq) -->'),
          reason:
              'append u6e landing gate acceptance comment after tentura-5zq on '
              'alloy/tentura-5zq trial merge remediation',
        );
      },
    );
  });
}

File _resolveRepoRelative(String path) {
  final repo = repoRootFromServerPackage();
  if (path.startsWith('test/architecture/')) {
    return File('${serverPackageRoot().path}/$path');
  }
  return File('${repo.path}/$path');
}

File _repoFile(String relativePath) {
  final repo = repoRootFromServerPackage();
  final candidate = File('${repo.path}/$relativePath');
  if (!candidate.existsSync()) {
    throw StateError('Repo file not found: ${candidate.path}');
  }
  return candidate;
}
