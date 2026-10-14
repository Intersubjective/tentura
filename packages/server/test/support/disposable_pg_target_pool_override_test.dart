import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

const _overrideVar = 'TENTURA_TEST_PG_POOL_SIZE';

Future<Map<String, dynamic>> _probe({
  String? override,
  String? ambientMaxConn,
}) async {
  final environment = {
    ...Platform.environment,
    _overrideVar: ?override,
    'POSTGRES_MAXCONN': ?ambientMaxConn,
  };
  final result = await Process.run(
    Platform.resolvedExecutable,
    ['test/support/disposable_pg_target_pool_override_probe.dart'],
    workingDirectory: Directory.current.path,
    environment: {
      for (final entry in environment.entries)
        if (override != null || entry.key != _overrideVar)
          entry.key: entry.value,
    },
  );
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return jsonDecode((result.stdout as String).trim().split('\n').last)
      as Map<String, dynamic>;
}

/// Database-free: runs on the shard without Postgres.
void main() {
  group('pool-size-1 mode resolution of the disposable PG target', () {
    test(
      'the test pool override wins over an ambient POSTGRES_MAXCONN for '
      'every disposable-target Env',
      () async {
        final snapshot = await _probe(override: '1', ambientMaxConn: '4');
        expect(snapshot['database'], 1);
        expect(snapshot['admin'], 1);
        expect(snapshot['template'], 1);
      },
    );

    test('the test pool override also caps constellation DB admission and '
        'the main pool admission at one slot', () async {
      final snapshot = await _probe(override: '1', ambientMaxConn: '4');
      expect(snapshot['constellationDbMaxConcurrent'], 1);
      expect(snapshot['admissionSlots'], 1);
    });

    test(
      'without the override the ambient pool size is still honoured',
      () async {
        final snapshot = await _probe(ambientMaxConn: '4');
        expect(snapshot['database'], 4);
        expect(snapshot['admissionSlots'], 4);
      },
    );
  });
}
