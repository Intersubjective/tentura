@Tags(['pg'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';

/// A constellation transaction (`withMutatingRepeatableRead`) bounds each of
/// its statements by the request budget it was given as `deadline`, so a stuck
/// MeritRank call inside it is cancelled at the budget instead of holding the
/// worker's only connection for the connection-wide 30 s limit. The limit is
/// transaction-local (`SET LOCAL`): the next transaction on the same
/// connection is bounded by the connection-wide setting again.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_MUTATING_RR_STATEMENT_TIMEOUT_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_mut_rr_stmt_timeout',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for statement timeout PG test';

  const connectionTimeoutMs = 30000;

  TenturaDb openDb() {
    final base = target.databaseEnv;
    final db = TenturaDb(
      Env(
        environment: Environment.test,
        pgHost: base.pgHost,
        pgPort: base.pgPort,
        pgDatabase: base.pgDatabase,
        pgUsername: base.pgUsername,
        pgPassword: base.pgPassword,
        pgStatementTimeoutMs: connectionTimeoutMs,
        printEnv: false,
        isDebugModeOn: false,
      ),
    );
    addTearDown(db.close);
    return db;
  }

  Future<int> statementTimeoutMs(TenturaDb db) async {
    final row = await db.customSelect('''
SELECT (extract(epoch FROM current_setting('statement_timeout')::interval)
        * 1000)::bigint AS ms
''').getSingle();
    return row.read<int>('ms');
  }

  group('constellation transaction statement_timeout', () {
    setUpAll(() async {
      if (skipReason != false) return;
      await target.recreate();
    });

    tearDownAll(() async {
      if (skipReason != false) return;
      await target.drop();
    });

    test(
      'equals the request budget while the transaction runs',
      () async {
        final db = openDb();
        final inside = await db.withMutatingRepeatableRead(
          'Ubudgetuser0001',
          () => statementTimeoutMs(db),
          deadline: const Duration(milliseconds: 1500),
        );
        expect(inside, 1500);
      },
      skip: skipReason,
    );

    test(
      'follows a different request budget per call',
      () async {
        final db = openDb();
        final short = await db.withMutatingRepeatableRead(
          'Ubudgetuser0001',
          () => statementTimeoutMs(db),
          deadline: const Duration(milliseconds: 700),
        );
        final long = await db.withMutatingRepeatableRead(
          'Ubudgetuser0001',
          () => statementTimeoutMs(db),
          deadline: const Duration(seconds: 4),
        );
        expect(short, 700);
        expect(long, 4000);
      },
      skip: skipReason,
    );

    test(
      'keeps the repeatable-read isolation and mutating actor context',
      () async {
        final db = openDb();
        final row = await db.withMutatingRepeatableRead(
          'Ubudgetuser0001',
          () => db.customSelect('''
SELECT current_setting('transaction_isolation') AS isolation,
       current_setting('tentura.mutating_user_id') AS actor
''').getSingle(),
          deadline: const Duration(seconds: 2),
        );
        expect(row.read<String>('isolation'), 'repeatable read');
        expect(row.read<String>('actor'), 'Ubudgetuser0001');
      },
      skip: skipReason,
    );

    test(
      'bounds the statements of a retried attempt too, never above the budget',
      () async {
        final db = openDb();
        var attempts = 0;
        final seen = <int>[];
        await db.withMutatingRepeatableRead(
          'Ubudgetuser0001',
          () async {
            attempts++;
            seen.add(await statementTimeoutMs(db));
            if (attempts == 1) {
              await db.customStatement(
                r"DO $$ BEGIN RAISE EXCEPTION USING ERRCODE = '40001'; END $$",
              );
            }
          },
          deadline: const Duration(seconds: 3),
          sleep: (_) async {},
        );
        expect(attempts, 2, reason: 'The 40001 must retry the whole attempt.');
        expect(seen.first, 3000);
        expect(
          seen.last,
          inInclusiveRange(1, 3000),
          reason:
              'A retry must not fall back to the connection-wide '
              '$connectionTimeoutMs ms nor stretch the request budget.',
        );
      },
      skip: skipReason,
    );

    test(
      'is transaction-local: the connection-wide limit applies again after '
      'commit',
      () async {
        final db = openDb();
        await db.withMutatingRepeatableRead(
          'Ubudgetuser0001',
          () => statementTimeoutMs(db),
          deadline: const Duration(milliseconds: 1500),
        );
        expect(await statementTimeoutMs(db), connectionTimeoutMs);
      },
      skip: skipReason,
    );

    test(
      'a statement running past the budget is cancelled at the budget and '
      'the connection is reusable',
      () async {
        final db = openDb();
        final pidBefore =
            (await db
                    .customSelect('SELECT pg_backend_pid() AS pid')
                    .getSingle())
                .read<int>('pid');

        final clock = Stopwatch()..start();
        await expectLater(
          db.withMutatingRepeatableRead(
            'Ubudgetuser0001',
            () => db.customSelect('SELECT pg_sleep(5)').get(),
            deadline: const Duration(milliseconds: 400),
          ),
          throwsA(
            isA<ServerException>().having(
              (e) => e.code,
              'SQLSTATE',
              '57014',
            ),
          ),
        );
        clock.stop();
        expect(
          clock.elapsed,
          lessThan(const Duration(milliseconds: 400 + 100)),
          reason:
              'The cancel must come from the budget, not from the 5 s '
              'sleep finishing or the 30 s connection limit.',
        );

        final after = await db
            .customSelect('SELECT pg_backend_pid() AS pid, 1 AS one')
            .getSingle();
        expect(after.read<int>('one'), 1);
        expect(after.read<int>('pid'), pidBefore);
        expect(await statementTimeoutMs(db), connectionTimeoutMs);
      },
      skip: skipReason,
    );
  });
}
