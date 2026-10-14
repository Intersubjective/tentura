// Runs the same selection the pool-size-1 CI command uses, on small targets,
// in a child `dart test` process: the override must reach the disposable
// database of a real pg test, and the multi-connection tag must keep
// deliberately multi-connection tests out of that run.

import 'dart:io';

import 'package:test/test.dart';

const _overrideVar = 'TENTURA_TEST_PG_POOL_SIZE';

Future<ProcessResult> _dartTest(
  List<String> args, {
  Map<String, String> environment = const {},
}) => Process.run(
  Platform.resolvedExecutable,
  ['test', '--reporter=expanded', ...args],
  workingDirectory: Directory.current.path,
  environment: {
    for (final e in Platform.environment.entries)
      if (e.key != _overrideVar) e.key: e.value,
    ...environment,
  },
);

void main() {
  group('pool-size-1 run of pg tests', () {
    test('a pg test passes under the pool override, so the override reaches '
        'the disposable database', () async {
      final result = await _dartTest(
        [
          '--tags',
          'pg',
          '--exclude-tags',
          'mr,multi-connection',
          'test/data/database/pool_size_override_applies_pg_test.dart',
        ],
        environment: {_overrideVar: '1'},
      );
      expect(
        result.exitCode,
        0,
        reason: '${result.stdout}\n${result.stderr}',
      );
      expect(result.stdout, contains('All tests passed'));
    });

    test('a pg test that sizes its own pool is excluded from the pool-size-1 '
        'selection', () async {
      final result = await _dartTest(
        [
          '--tags',
          'pg',
          '--exclude-tags',
          'mr,multi-connection',
          'test/data/database/tentura_db_shared_pool_savepoint_pg_test.dart',
        ],
        environment: {_overrideVar: '1'},
      );
      expect(
        '${result.stdout}${result.stderr}',
        contains('No tests ran'),
        reason: 'the multi-connection test must not run in this selection',
      );
    });
  }, timeout: const Timeout(Duration(minutes: 5)));
}
