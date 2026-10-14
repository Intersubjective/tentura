@Tags(['pg'])
library;

import 'dart:io';

import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';

const _overrideVar = 'TENTURA_TEST_PG_POOL_SIZE';

/// Sentinel for the pool-size-1 run of the functional PG suite: when the
/// override is set, the disposable database really runs with that many
/// pooled connections, and ordinary scoped work (nested transactions) still
/// completes on it.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POOL_OVERRIDE_APPLIES_TEST_DB',
    defaultNamePrefix: 'tentura_test_pool_override_applies',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }

  final requested = int.tryParse(Platform.environment[_overrideVar] ?? '');

  late DisposablePgWriterSession session;
  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
  });
  tearDownAll(() => tearDownDisposablePgWriter(session: session));

  test('the disposable database pool has the size requested by the test '
      'override', () {
    if (requested == null) return;
    expect(target.databaseEnv.pgPoolSettings.maxConnectionCount, requested);
  });

  test('nested transactions complete on a scope of the disposable '
      'database', () async {
    final db = openDisposablePgDatabase(target);
    try {
      final value = await db.transaction(
        () => db.transaction(
          () async => (await db.customSelect('SELECT 1 AS v').getSingle())
              .read<int>('v'),
        ),
      );
      expect(value, 1);
    } finally {
      await db.close();
    }
  });
}
