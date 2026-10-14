@Tags(['pg', 'multi-connection'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';

const _overrideVar = 'TENTURA_TEST_PG_POOL_SIZE';

Future<Map<String, dynamic>> _runProbe() async {
  final result = await Process.run(
    Platform.resolvedExecutable,
    ['test/support/single_connection_cross_handle_probe.dart'],
    workingDirectory: Directory.current.path,
    environment: {
      ...Platform.environment,
      _overrideVar: '1',
      'POSTGRES_MAXCONN': '4',
    },
  );
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return jsonDecode((result.stdout as String).trim().split('\n').last)
      as Map<String, dynamic>;
}

/// Under the pool-size-1 test mode one unit of work holds the only
/// connection, so a second database handle that tried to lease its own
/// connection (the lease re-entry that once hung the suite) cannot be hidden
/// by a spare connection.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_SINGLE_CONNECTION_REENTRY_TEST_DB',
    defaultNamePrefix: 'tentura_test_single_conn_reentry',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }

  group('database handles sharing a one-connection pool', () {
    late Map<String, dynamic> outcome;

    setUpAll(() async => outcome = await _runProbe());

    test('the pool really has a single connection and admission slot', () {
      expect(outcome['poolCapacity'], 1);
      expect(outcome['admissionSlots'], 1);
    });

    test('a nested handle inside a unit of work reuses the held connection '
        'instead of waiting for a second one', () {
      expect(outcome['sameLease'], 'reused');
    });

    test('a handle outside the held scope cannot take a second connection, '
        'and fails promptly instead of hanging', () {
      expect(outcome['escapedHandle'], 'refused');
    });

    test('a second unrelated admission is refused while the only slot is '
        'held, instead of using a spare connection', () {
      expect(outcome['secondAdmission'], 'refused');
    });
  }, timeout: const Timeout(Duration(minutes: 2)));
}
