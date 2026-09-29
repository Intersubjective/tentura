// tentura-5zq landing gate acceptance (parent tentura-617.3)

import 'dart:io';

import 'package:test/test.dart';

import '../support/server_ci_lint_gate_harness.dart';

/// Alloy tentura-5zq — same paths as bead acceptance harness.
const k5zqAcceptanceTestPaths = [
  'test/architecture/tentura_5zq_server_ci_analyze_gate_test.dart',
  'test/alloy_landing_gate_5zq_test.dart',
  'test/architecture/tentura_u6e_landing_check_test.dart',
  'test/alloy_landing_gate_u6e_test.dart',
  'test/tentura_499_wrapped_selftest_landing_check_test.dart',
];

/// Paths that must carry the tentura-5zq landing gate marker (not u6e remediation).
const _k5zqLandingGateMarkerTestPaths = [
  'test/architecture/tentura_5zq_server_ci_analyze_gate_test.dart',
  'test/alloy_landing_gate_5zq_test.dart',
];

const _5zqLandingGateMarker =
    'tentura-5zq landing gate acceptance (parent tentura-617.3)';

const _parentBeadMarker = 'parent tentura-617.3';

const _harnessImport =
    "import '../support/server_ci_lint_gate_harness.dart'";

/// The u6e bead acceptance runs the whole non-pg suite nested; the heavy
/// analyze/lint subprocess gates below must not run again inside it (they
/// still run in CI and in targeted acceptance runs, where the flag is unset).
Object get _skipInU6eNestedSuite {
  if (Platform.environment['TENTURA_U6E_NESTED_SUITE'] == 'true') {
    return 'do not nest full-package dart analyze inside the u6e nested suite';
  }
  return false;
}

void main() {
  group('tentura-5zq server CI analyze gate (parent tentura-617.3)', () {
    test('5zq acceptance test paths declare 5zq landing gate markers', () {
      for (final path in _k5zqLandingGateMarkerTestPaths) {
        final resolved = _resolveRepoRelative(path);
        expect(resolved.existsSync(), isTrue, reason: 'missing acceptance path $path');
        final source = resolved.readAsStringSync();
        expect(
          source,
          contains(_5zqLandingGateMarker),
          reason:
              '$path must tag the 5zq landing gate for Alloy trial-merge tracking',
        );
        expect(
          source,
          contains(_parentBeadMarker),
          reason: '$path must reference parent bead tentura-617.3',
        );
      }
    });

    test(
      'package analyze reports zero errors; cited outside-diff line stays non-error debt',
      () {
        final summary = summarizePackageWideDartAnalyze();
        expect(
          summary.errorCount,
          0,
          reason:
              'tentura-5zq bead evidence: package-wide analyze has 0 errors; '
              'failures are warnings/infos or exit code, not new errors\n'
              '${summary.errorLines.join('\n')}',
        );

        final cited = diagnosticsOnServerRelativeLine(
          k5zqCitedOutsideDiffRelative,
          k5zqCitedOutsideDiffLineOneBased,
        );
        for (final d in cited) {
          expect(
            d['severity'],
            isNot('ERROR'),
            reason:
                'pre-existing diagnostic at '
                '${k5zqCitedOutsideDiffRelative}:'
                '${k5zqCitedOutsideDiffLineOneBased} must not be an error',
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 12)),
      skip: _skipInU6eNestedSuite,
    );

    test(
      'CI gate uses dart analyze --no-fatal-warnings and passes while bare dart analyze . may be stricter',
      () {
        final script = readCheckCustomLintsScriptFromRepo();
        expect(
          script,
          contains('dart analyze --no-fatal-warnings'),
          reason:
              'check-custom-lints.sh must match CI (non-fatal warnings)',
        );

        final ci = runServerCiLintGateFromRepoRoot();
        expect(
          ci.exitCode,
          0,
          reason:
              'CI-equivalent gate must pass\n'
              'stdout:\n${ci.stdout}\nstderr:\n${ci.stderr}',
        );
        expect(
          ci.stdout,
          contains('check-custom-lints: packages/server OK'),
        );

        final noFatal = runDartAnalyzeDotNoFatalWarningsInServerPackage();
        expect(
          noFatal.exitCode,
          0,
          reason:
              'dart analyze --no-fatal-warnings . must pass (same flags as CI script)\n'
              '${noFatal.stdout}\n${noFatal.stderr}',
        );

        final bare = runBareDartAnalyzeDotInServerPackage();
        final summary = summarizePackageWideDartAnalyze();
        if (bare.exitCode != 0) {
          expect(
            summary.errorCount,
            0,
            reason:
                'tentura-5zq defect: bare `dart analyze .` exit ${bare.exitCode} '
                'with ${summary.warningCount} warnings and '
                '${summary.infoCount} infos but 0 errors — CI gate must still pass',
          );
          expect(ci.exitCode, 0);
        }
      },
      timeout: const Timeout(Duration(minutes: 15)),
      skip: _skipInU6eNestedSuite,
    );

    test(
      'tentura-olc harness imports shared runner and executes bead acceptance at runtime',
      () {
        final olc = olcLandingCheckTestFile();
        final source = olc.readAsStringSync();
        expect(source, contains(_harnessImport));
        expect(
          source,
          contains('runOlcAcceptanceServerLintGate()'),
          reason:
              'olc bead acceptance must call the shared CI gate runner, not a '
              'local dart analyze subprocess',
        );
        expect(
          source,
          isNot(contains("'dart', 'analyze', '.'")),
          reason: 'remove bare dart analyze . from olc acceptance runner',
        );

        final runtime = runOlcBeadAcceptanceDartTest();
        expect(
          runtime.exitCode,
          0,
          reason:
              'tentura-olc runtime bead acceptance must run '
              '$kOlcBeadAcceptanceTestName via check-custom-lints\n'
              'stdout:\n${runtime.stdout}\nstderr:\n${runtime.stderr}',
        );
      },
      timeout: const Timeout(Duration(minutes: 15)),
      skip: _skipInU6eNestedSuite,
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
