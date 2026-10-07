@Tags(['pg'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';

/// Request-path connections (the web workers' [TenturaDb]) bound every single
/// statement, so one runaway query cannot hold an isolate's only pool
/// connection indefinitely. Connections opened with the plain endpoint
/// settings — the migration connection in `App.run` and the task worker's —
/// stay unbounded.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_STATEMENT_TIMEOUT_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_stmt_timeout',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for statement timeout PG test';

  Env envWith({int? statementTimeoutMs}) {
    final base = target.databaseEnv;
    return Env(
      environment: Environment.test,
      pgHost: base.pgHost,
      pgPort: base.pgPort,
      pgDatabase: base.pgDatabase,
      pgUsername: base.pgUsername,
      pgPassword: base.pgPassword,
      pgStatementTimeoutMs: statementTimeoutMs,
      printEnv: false,
      isDebugModeOn: false,
    );
  }

  Future<String> currentTimeout(TenturaDb db) async {
    final row = await db
        .customSelect("SELECT current_setting('statement_timeout') AS v")
        .getSingle();
    return row.read<String>('v');
  }

  group('request-path connection statement_timeout', () {
    setUpAll(() async {
      if (skipReason != false) return;
      await target.recreate();
    });

    tearDownAll(() async {
      if (skipReason != false) return;
      await target.drop();
    });

    test(
      'defaults to 30 seconds',
      () async {
        final db = TenturaDb(envWith());
        addTearDown(db.close);
        expect(await currentTimeout(db), '30s');
      },
      skip: skipReason,
    );

    test(
      'follows the configured millisecond value',
      () async {
        final db = TenturaDb(envWith(statementTimeoutMs: 200));
        addTearDown(db.close);
        expect(await currentTimeout(db), '200ms');
      },
      skip: skipReason,
    );

    test(
      'applies inside a transaction on the same connection',
      () async {
        final db = TenturaDb(envWith(statementTimeoutMs: 200));
        addTearDown(db.close);
        expect(await db.transaction(() => currentTimeout(db)), '200ms');
      },
      skip: skipReason,
    );

    test(
      'a statement running past the limit is cancelled with SQLSTATE 57014 '
      'and the next statement on the same connection succeeds',
      () async {
        final db = TenturaDb(envWith(statementTimeoutMs: 200));
        addTearDown(db.close);

        final pidBefore = (await db
                .customSelect('SELECT pg_backend_pid() AS pid')
                .getSingle())
            .read<int>('pid');

        await expectLater(
          db.customSelect('SELECT pg_sleep(1)').get(),
          throwsA(
            isA<ServerException>().having(
              (e) => e.code,
              'SQLSTATE',
              '57014',
            ),
          ),
        );

        final after = await db
            .customSelect('SELECT pg_backend_pid() AS pid, 1 AS one')
            .getSingle();
        expect(after.read<int>('one'), 1);
        expect(after.read<int>('pid'), pidBefore);
        expect(await currentTimeout(db), '200ms');
      },
      skip: skipReason,
    );

    test(
      'a transaction statement past the limit does not poison the next '
      'transaction',
      () async {
        final db = TenturaDb(envWith(statementTimeoutMs: 200));
        addTearDown(db.close);

        await expectLater(
          db.transaction(
            () => db.customSelect('SELECT pg_sleep(1)').get(),
          ),
          throwsA(
            isA<ServerException>().having(
              (e) => e.code,
              'SQLSTATE',
              '57014',
            ),
          ),
        );

        final one = await db.transaction(
          () => db.customSelect('SELECT 1 AS one').getSingle(),
        );
        expect(one.read<int>('one'), 1);
      },
      skip: skipReason,
    );
  });

  group('connections outside the request path keep statement_timeout 0', () {
    setUpAll(() async {
      if (skipReason != false) return;
      await target.recreate();
    });

    tearDownAll(() async {
      if (skipReason != false) return;
      await target.drop();
    });

    // Opened exactly as App.run (migration) and TaskWorker.create do, with a
    // request-path knob configured: the knob must not leak into them.
    for (final entry in {
      'migration connection': 200,
      'task worker connection': 200,
    }.entries) {
      test(
        '${entry.key} reports 0 although the request-path knob is set',
        () async {
          final env = envWith(statementTimeoutMs: entry.value);
          final connection = await Connection.open(
            env.pgEndpoint,
            settings: env.pgEndpointSettings,
          );
          addTearDown(connection.close);
          final rows = await connection.execute(
            "SELECT current_setting('statement_timeout')",
          );
          expect(rows.single.single, '0');
        },
        skip: skipReason,
      );
    }
  });
}
