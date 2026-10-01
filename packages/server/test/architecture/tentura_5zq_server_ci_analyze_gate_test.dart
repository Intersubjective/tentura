// tentura-5zq server CI analyze gate (parent tentura-617.3)

import 'package:test/test.dart';

import '../support/server_ci_lint_gate_harness.dart';

void main() {
  group('tentura-5zq server CI analyze gate (parent tentura-617.3)', () {
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
    );

    test(
      'CI gate uses dart analyze --no-fatal-warnings and passes while bare dart analyze . may be stricter',
      () {
        final script = readCheckCustomLintsScriptFromRepo();
        expect(
          script,
          contains('dart analyze --no-fatal-warnings'),
          reason: 'check-custom-lints.sh must match CI (non-fatal warnings)',
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
    );
  });
}
