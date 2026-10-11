@Tags(['pg'])
library;

import 'dart:async';

import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart';

import '../../support/disposable_pg_target.dart';

/// A plain read holds Drift's executor lock while it picks a session. A
/// transaction that pins the only pool connection in between must not leave
/// the read waiting on the pool (it held the lock the transaction needs) until
/// the pool's connect timeout: TENTURA-SERVER-V/W, "Failed to acquire pool
/// lock" on reads during constellation anchor writes.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PINNED_POOL_RACE_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_pinned_pool_race',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  late TenturaDb database;

  setUpAll(() async {
    await target.recreate();
    database = TenturaDb(target.databaseEnv);
  });

  tearDownAll(() async {
    await database.close();
    await target.drop();
  });

  Future<void> afterMicrotasks(int count) async {
    for (var i = 0; i < count; i++) {
      await Future<void>.microtask(() {});
    }
  }

  test(
    'a transaction pinning while a read picks its session does not stall it',
    () async {
      // Sweep the transaction's start across the read's path to the pool so
      // one offset lands between its pin check and its pool request.
      for (var offset = 0; offset < 60; offset++) {
        final read = database.customSelect('SELECT 1 AS one').getSingle();
        final tx = afterMicrotasks(offset).then(
          (_) => database.transaction(
            () => database.customSelect('SELECT 2 AS two').getSingle(),
          ),
        );
        await Future.wait([read, tx]).timeout(
          const Duration(seconds: 3),
          onTimeout: () => fail('read and transaction stalled at $offset'),
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
