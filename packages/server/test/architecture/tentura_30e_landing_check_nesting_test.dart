// tentura-30e landing gate acceptance (fix tentura-pl4)

import 'dart:io';

import 'package:test/test.dart';

import '../support/server_ci_lint_gate_harness.dart';

/// Alloy tentura-30e — landing-check subprocess nesting remediation (parent pl4).
const k30eAcceptanceTestPaths = [
  'test/architecture/tentura_30e_landing_check_nesting_test.dart',
];

const _30eLandingGateMarker =
    'tentura-30e landing gate acceptance (fix tentura-pl4)';

const _parentLandingMarker = 'fix tentura-pl4';

const _pl4LandingCheckRelative =
    'test/architecture/tentura_pl4_landing_check_test.dart';

const _agents30eLandingComment =
    '<!-- tentura-30e landing gate acceptance (fix tentura-pl4) -->';

/// Landing gates that spawn wrapped full-suite `dart test` runs and must not
/// re-enter when a parent landing gate already nested a suite (tentura-30e).
const k30eReentrantLandingCheckRelativePaths = [
  'test/architecture/tentura_pl4_landing_check_test.dart',
  'test/architecture/tentura_u6e_landing_check_test.dart',
  'test/architecture/tentura_fx7_landing_check_test.dart',
  'test/architecture/tentura_j0q_landing_check_test.dart',
];

const _fx7LandingCheckRelative =
    'test/architecture/tentura_fx7_landing_check_test.dart';

const _j0qLandingCheckRelative =
    'test/architecture/tentura_j0q_landing_check_test.dart';

const _pl4NestedRunnerName = 'runPl4AcceptanceNonPgDartTest';

const _u6eNestedRunnerName = 'runU6eAcceptanceNonPgDartTest';

const _fx7PgLandingRunnerName = 'runFx7AcceptancePgLanding';

const _j0qPgLandingRunnerName = 'runJ0qAcceptancePgLanding';

const _harness30ePolicyName = 'k30eReentrantLandingCheckRelativePaths';

const _harnessNonPgArgsHelper = 'nonPgNestedLandingDartTestArgs';

const _harnessPgChildEnvHelper = 'nestedPgLandingSuiteChildEnvironment';

void main() {
  group('tentura-30e landing check nesting (fix tentura-pl4)', () {
    test('30e acceptance test paths declare 30e landing gate markers', () {
      for (final path in k30eAcceptanceTestPaths) {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: 'missing acceptance path $path');
        final source = file.readAsStringSync();
        expect(
          source,
          contains(_30eLandingGateMarker),
          reason:
              '$path must tag the 30e landing gate for Alloy trial-merge tracking',
        );
        expect(
          source,
          contains(_parentLandingMarker),
          reason: '$path must reference parent landing bead tentura-pl4',
        );
      }
    });

    test(
      'tentura-pl4 parent landing gate lists 30e acceptance paths',
      () {
        final source = File(
          '${serverPackageRoot().path}/$_pl4LandingCheckRelative',
        ).readAsStringSync();
        for (final path in k30eAcceptanceTestPaths) {
          expect(
            source,
            contains("'$path'"),
            reason:
                '$_pl4LandingCheckRelative must list $path so Alloy '
                'tentura-pl4 landing tracks tentura-30e nesting remediation',
          );
        }
      },
    );

    test(
      'server CI harness exports tentura-30e re-entrant landing-check inventory',
      () {
        final harness = File(
          '${serverPackageRoot().path}/test/support/server_ci_lint_gate_harness.dart',
        ).readAsStringSync();
        expect(
          harness,
          contains(_harness30ePolicyName),
          reason:
              'server_ci_lint_gate_harness must define $_harness30ePolicyName '
              'so nested non-pg landing runs can exclude subprocess landing gates',
        );
        for (final path in k30eReentrantLandingCheckRelativePaths) {
          expect(
            harness,
            contains("'$path'"),
            reason:
                '$_harness30ePolicyName must list $path (tentura-30e bead evidence)',
          );
        }
      },
    );

    test(
      'non-pg nested landing runners use shared exclude args helper',
      () {
        final harness = File(
          '${serverPackageRoot().path}/test/support/server_ci_lint_gate_harness.dart',
        ).readAsStringSync();
        expect(
          harness,
          contains(_harnessNonPgArgsHelper),
          reason:
              'harness must centralize nested non-pg dart test argv via '
              '$_harnessNonPgArgsHelper',
        );
        for (final runner in [_pl4NestedRunnerName, _u6eNestedRunnerName]) {
          expect(
            _functionBody(harness, runner),
            contains(_harnessNonPgArgsHelper),
            reason:
                '$runner must spread $_harnessNonPgArgsHelper so nested '
                'suites never re-enter landing-check subprocess gates',
          );
        }
      },
    );

    test(
      'pl4 landing check delegates nested non-pg runner to harness only',
      () {
        final source = File(
          '${serverPackageRoot().path}/test/architecture/tentura_pl4_landing_check_test.dart',
        ).readAsStringSync();
        expect(
          source,
          isNot(contains('CommandOutcome runPl4AcceptanceNonPgDartTest')),
          reason:
              'tentura_pl4_landing_check_test must not duplicate '
              'runPl4AcceptanceNonPgDartTest; use harness helper (tentura-30e)',
        );
        expect(
          source,
          contains('runPl4AcceptanceNonPgDartTest()'),
          reason: 'pl4 bead acceptance must still invoke harness runner',
        );
      },
    );

    test(
      'fx7 and j0q pg landing runners propagate nested-suite skip env to children',
      () {
        final harness = File(
          '${serverPackageRoot().path}/test/support/server_ci_lint_gate_harness.dart',
        ).readAsStringSync();
        expect(
          harness,
          contains(_harnessPgChildEnvHelper),
          reason:
              'harness must define $_harnessPgChildEnvHelper for nested full-pg '
              'landing acceptance subprocesses',
        );
        for (final runner in [_fx7PgLandingRunnerName, _j0qPgLandingRunnerName]) {
          expect(
            harness,
            contains('$runner('),
            reason:
                '$_fx7LandingCheckRelative / $_j0qLandingCheckRelative nested '
                'pg landing must move to harness as $runner (tentura-30e)',
          );
          final body = _functionBody(harness, runner);
          expect(
            body,
            contains(_harnessPgChildEnvHelper),
            reason:
                '$runner must merge $_harnessPgChildEnvHelper into Process env '
                'so inner suites skip re-entrant landing-check subprocess tests',
          );
        }
      },
    );

    test(
      'fx7 landing check does not define a local nested full-pg runner',
      () {
        final source = File(
          '${serverPackageRoot().path}/$_fx7LandingCheckRelative',
        ).readAsStringSync();
        expect(
          source,
          isNot(contains('runFx7AcceptancePgLanding() {')),
          reason:
              '$_fx7LandingCheckRelative must not define a local '
              'runFx7AcceptancePgLanding after tentura-30e harness centralization',
        );
      },
    );

    test(
      'j0q landing check does not define a local nested full-pg runner',
      () {
        final source = File(
          '${serverPackageRoot().path}/$_j0qLandingCheckRelative',
        ).readAsStringSync();
        expect(
          source,
          isNot(contains('runJ0qAcceptancePgLanding() {')),
          reason:
              '$_j0qLandingCheckRelative must not define a local '
              'runJ0qAcceptancePgLanding after tentura-30e harness centralization',
        );
      },
    );

    test(
      'AGENTS.md records tentura-30e landing gate acceptance beside prior trial merges',
      () {
        final agents = _repoFile('AGENTS.md').readAsStringSync();
        expect(
          agents,
          contains(_agents30eLandingComment),
          reason:
              'append $_agents30eLandingComment after tentura-3i0m on '
              'tentura-pl4 nesting remediation',
        );
      },
    );

    test(
      'harness nested landing policy caps subprocess suite depth at one',
      () {
        final harness = File(
          '${serverPackageRoot().path}/test/support/server_ci_lint_gate_harness.dart',
        ).readAsStringSync();
        expect(
          harness,
          contains('const maxNestedLandingSuiteDepth = 1'),
          reason:
              'nested landing gates must not stack full-suite subprocesses '
              '(observed: four nested "Failing tests:" blocks on tentura-pl4)',
        );
      },
    );
  });
}

/// Extracts a top-level function body from [source] (best-effort for harness tests).
String _functionBody(String source, String functionName) {
  final start = source.indexOf('$functionName(');
  if (start < 0) {
    return '';
  }
  final brace = source.indexOf('{', start);
  if (brace < 0) {
    return '';
  }
  var depth = 0;
  for (var i = brace; i < source.length; i++) {
    final ch = source[i];
    if (ch == '{') {
      depth++;
    } else if (ch == '}') {
      depth--;
      if (depth == 0) {
        return source.substring(start, i + 1);
      }
    }
  }
  return source.substring(start);
}

File _repoFile(String relativePath) {
  final repo = repoRootFromServerPackage();
  final candidate = File('${repo.path}/$relativePath');
  if (!candidate.existsSync()) {
    throw StateError('Repo file not found: ${candidate.path}');
  }
  return candidate;
}
