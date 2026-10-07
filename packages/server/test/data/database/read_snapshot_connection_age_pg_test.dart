@Tags(['pg'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_READ_SNAPSHOT_AGE_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_rsnapage',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for read snapshot PG test';

  group('TenturaDb transactions when the pool connection ages out', () {
    late TenturaDb db;

    setUpAll(() async {
      if (skipReason != false) {
        return;
      }
      await target.recreate();
      final base = target.databaseEnv;
      db = TenturaDb(
        Env(
          environment: Environment.test,
          pgHost: base.pgHost,
          pgPort: base.pgPort,
          pgDatabase: base.pgDatabase,
          pgUsername: base.pgUsername,
          pgPassword: base.pgPassword,
          // Shortest possible age so the pool wants to replace the session
          // while a transaction is still open.
          maxConnectionAge: 1,
          printEnv: false,
          isDebugModeOn: false,
        ),
      );
    });

    tearDownAll(() async {
      if (skipReason != false) {
        return;
      }
      await db.close();
      await target.drop();
    });

    /// Backend session and transaction start time as seen by one statement.
    /// `now()` is frozen for the life of a transaction, so equal values across
    /// a delay prove the later statement ran inside the same transaction on the
    /// same session (an autocommit statement on a replaced session would
    /// report a different pid and a later `now()`).
    Future<({int pid, int startedAtMicros})> sessionProbe() async {
      final row = await db
          .customSelect(
            'SELECT pg_backend_pid() AS pid, '
            '(extract(epoch FROM now()) * 1000000)::bigint AS started_us',
          )
          .getSingle();
      return (
        pid: row.read<int>('pid'),
        startedAtMicros: row.read<int>('started_us'),
      );
    }

    const ageElapsed = Duration(milliseconds: 2500);

    test(
      'read snapshot keeps later statements on the same session and '
      'transaction after the connection age elapses',
      () async {
        final (before, after) = await db.withReadSnapshot(() async {
          final first = await sessionProbe();
          await Future<void>.delayed(ageElapsed);
          return (first, await sessionProbe());
        });
        expect(after.pid, before.pid);
        expect(after.startedAtMicros, before.startedAtMicros);
      },
      skip: skipReason,
    );

    test(
      'nested transaction savepoint runs inside the outer transaction on the '
      'same session after the connection age elapses',
      () async {
        final (before, after) = await db.transaction(() async {
          final first = await sessionProbe();
          await Future<void>.delayed(ageElapsed);
          final second = await db.transaction(sessionProbe);
          return (first, second);
        });
        expect(after.pid, before.pid);
        expect(after.startedAtMicros, before.startedAtMicros);
      },
      skip: skipReason,
    );
  });
}
