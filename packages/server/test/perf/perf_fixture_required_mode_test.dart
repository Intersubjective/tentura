import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  for (final runner in [
    'perf_fixture_matrix_pg_only_pg_test.dart',
    'perf_fixture_matrix_meritrank_pg_test.dart',
  ]) {
    group(runner, () {
      for (final required in [false, true]) {
        test(
          'unreachable PostgreSQL ${required ? 'fails' : 'skips'} in '
          '${required ? 'required' : 'optional'} mode',
          () async {
            // Exercise the actual entry point, including its environment and
            // skip wiring. Port 1 refuses connections without touching a DB.
            final result = await Process.run(
              Platform.resolvedExecutable,
              ['test', 'test/perf/$runner', '--reporter=json', '-j', '1'],
              environment: {
                'POSTGRES_HOST': '127.0.0.1',
                'POSTGRES_PORT': '1',
                'POSTGRES_ADMIN_DBNAME': 'postgres',
                'TENTURA_PG_TESTS_REQUIRED': required ? '1' : '0',
                'TENTURA_PERF_MATRIX_ATTEMPTS': '1',
                'TENTURA_PERF_MATRIX_CASES': '',
                'TENTURA_PERF_MATRIX_PG_ONLY_TEST_DB':
                    'tentura_test_perf_required_pg',
                'TENTURA_PERF_MATRIX_MR_TEST_DB':
                    'tentura_test_perf_required_mr',
              },
            );
            final output = '${result.stdout}\n${result.stderr}';
            if (required) {
              expect(result.exitCode, isNot(0), reason: output);
              expect(
                output,
                contains(
                  'Postgres required (TENTURA_PG_TESTS_REQUIRED=1) '
                  'but not reachable',
                ),
              );
            } else {
              expect(result.exitCode, 0, reason: output);
              final events = (result.stdout as String)
                  .split('\n')
                  .where((line) => line.startsWith('{'))
                  .map((line) => jsonDecode(line) as Map<String, dynamic>)
                  .toList();
              final fixtures = events.where(
                (event) =>
                    event['type'] == 'testStart' &&
                    ((event['test'] as Map<String, dynamic>)['name'] as String)
                        .contains(' writes build/perf/'),
              );
              expect(fixtures, isNotEmpty, reason: output);
              for (final fixture in fixtures) {
                final test = fixture['test'] as Map<String, dynamic>;
                expect(
                  events,
                  contains(
                    allOf(
                      containsPair('type', 'testDone'),
                      containsPair('testID', test['id']),
                      containsPair('skipped', true),
                    ),
                  ),
                  reason: '${test['name']} must skip without PostgreSQL',
                );
              }
            }
          },
          timeout: const Timeout(Duration(minutes: 5)),
        );
      }
    });
  }
}
