@Tags(['pg'])
library;

import 'dart:io';

import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/hung_pg_self_wait_fixture.dart';

Future<String> _runFixture(String scenario) async {
  final result = await Process.run(
    Platform.resolvedExecutable,
    [
      'test',
      '--reporter=expanded',
      'test/support/hung_pg_self_wait_fixture.dart',
    ],
    workingDirectory: Directory.current.path,
    environment: {
      ...Platform.environment,
      hungSuiteScenarioEnvVar: scenario,
    },
  );
  expect(result.exitCode, isNot(0), reason: 'the fixture hangs on purpose');
  return '${result.stdout}\n${result.stderr}';
}

final _hardTimeout =
    'timed out after ${hungSuiteHardTimeout.inSeconds} seconds';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_HUNG_SUITE_DIAGNOSTICS_TEST_DB',
    defaultNamePrefix: 'tentura_test_hung_suite_diag',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }

  group(
    'a test hung on a database wait under the disposable-database harness',
    () {
      test(
        'a transaction waiting on a lock fails before the runner timeout and '
        'prints the scope stack and the blocked backend',
        () async {
          final output = await _runFixture(hungExecutorWaitScenario);

          expect(
            output,
            isNot(contains(_hardTimeout)),
            reason: 'the harness must end the wait itself:\n$output',
          );
          expect(output.toLowerCase(), contains('scope stack'));
          expect(output, contains(hungSuiteLockedStatement));
          expect(output, contains('advisory'));
          expect(output, contains('active'));
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );

      test(
        'a wait outside any Drift executor prints the database activity before '
        'the runner reports its timeout',
        () async {
          final output = await _runFixture(hungSuiteScenario);

          final timedOut = output.indexOf(_hardTimeout);
          expect(timedOut, isNonNegative, reason: output);
          final dump = output.indexOf('pg_stat_activity');
          expect(
            dump,
            allOf(isNonNegative, lessThan(timedOut)),
            reason: 'the dump must precede the runner timeout:\n$output',
          );
          expect(output, contains(hungSuiteLockedStatement));
          expect(output, contains('advisory'));
          expect(output, contains('active'));
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
    },
  );
}
