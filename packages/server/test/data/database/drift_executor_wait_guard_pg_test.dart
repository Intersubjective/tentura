@Tags(['pg'])
library;

import 'dart:async';

import 'package:drift_postgres/drift_postgres.dart';
import 'package:postgres/postgres.dart' show Connection;
import 'package:test/test.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;

import '../../support/disposable_pg_target.dart';
import '../../support/drift_executor_wait_guard.dart';

const _deadline = Duration(seconds: 2);
const _previousStatement = 'self_wait_previous_statement';
const _advisoryKey = 7240126;

/// Time a self-wait is allowed to take to surface, deadline included.
const _fewSeconds = Duration(seconds: 8);

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_EXECUTOR_WAIT_GUARD_TEST_DB',
    defaultNamePrefix: 'tentura_test_executor_wait_guard',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }

  late DisposablePgWriterSession session;
  final opened = <Connection>[];

  Future<Connection> openConnection() async {
    final connection = await Connection.open(
      target.databaseEnv.pgEndpoint,
      settings: target.databaseEnv.pgEndpointSettings,
    );
    opened.add(connection);
    return connection;
  }

  Future<int> backendPid(Connection connection) async {
    final rows = await connection.execute('SELECT pg_backend_pid()');
    return rows.first.first! as int;
  }

  Future<bool> backendGone(int pid) async {
    final clock = Stopwatch()..start();
    while (clock.elapsed < const Duration(seconds: 3)) {
      final rows = await readDbActivity(target);
      if (!rows.any((row) => row['pid'] == pid)) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return false;
  }

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
  });
  tearDown(() async {
    for (final connection in opened) {
      if (connection.isOpen) await connection.close();
    }
    opened.clear();
  });
  tearDownAll(() => tearDownDisposablePgWriter(session: session));

  group('database activity snapshot', () {
    test(
      'lists only the test database, with state, wait event and last query',
      () async {
        final connection = await openConnection();
        final pid = await backendPid(connection);
        await connection.execute('BEGIN');
        await connection.execute("SELECT '$_previousStatement'");

        final rows = await readDbActivity(target);

        expect(rows, isNotEmpty);
        expect(
          rows.map((row) => row['datname']).toSet(),
          {target.databaseName},
        );
        final mine = rows.singleWhere(
          (row) => row['pid'] == pid,
        );
        expect(mine['state'], 'idle in transaction');
        expect(mine['query'], contains(_previousStatement));
        expect(mine['wait_event_type'], 'Client');
        expect(mine['wait_event'], 'ClientRead');
        expect(
          rows.where(
            (row) =>
                '${row['query']}'.contains('pg_stat_activity'),
          ),
          isEmpty,
          reason: 'the admin probe must not report itself',
        );
        await connection.execute('ROLLBACK');
      },
    );

    test('reports the lock a blocked backend is waiting on', () async {
      final holder = await openConnection();
      await holder.execute('SELECT pg_advisory_lock($_advisoryKey)');
      final waiter = await openConnection();
      final waiterPid = await backendPid(waiter);
      final waiting = waiter.execute('SELECT pg_advisory_lock($_advisoryKey)');

      Map<String, Object?>? row;
      final clock = Stopwatch()..start();
      while (row == null && clock.elapsed < const Duration(seconds: 10)) {
        final rows = await readDbActivity(target);
        row = rows
            .where(
              (r) =>
                  r['pid'] == waiterPid && r['wait_event'] != null,
            )
            .firstOrNull;
        if (row == null) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }

      expect(row, isNotNull);
      expect(row!['state'], 'active');
      expect(row['wait_event_type'], 'Lock');
      expect(row['wait_event'], 'advisory');
      expect('${row['query']}', contains('pg_advisory_lock'));
      await holder.execute('SELECT pg_advisory_unlock($_advisoryKey)');
      await waiting;
    });
  });

  group('self-wait on a Drift executor', () {
    test(
      'a statement sent to the root executor while a transaction holds it '
      'fails within seconds with the scope stack and backend activity',
      () async {
        final connection = await openConnection();
        final pid = await backendPid(connection);
        final guard = DbWaitGuard.forTarget(target, deadline: _deadline);
        final root = PgDatabase.opened(
          connection,
          enableMigrations: false,
        ).interceptWith(guard);
        final db = TenturaDb.forTest(database: root);
        await db.customSelect('SELECT 1').get();
        final clock = Stopwatch()..start();

        Object? failure;
        try {
          await db
              .transaction(() async {
                await db.customSelect("SELECT '$_previousStatement'").get();
                await root.runSelect('SELECT 1 AS stale_root_wait', const []);
              })
              .timeout(_fewSeconds);
        } on Object catch (error) {
          failure = error;
        }

        expect(failure, isA<DbWaitTimeoutException>());
        final timeout = failure! as DbWaitTimeoutException;
        expect(clock.elapsed, lessThan(_fewSeconds));
        expect(timeout.sql, contains('stale_root_wait'));
        expect(timeout.scopeStack, hasLength(1));
        final mine = timeout.activity.singleWhere(
          (row) => row['pid'] == pid,
        );
        expect(mine['state'], 'idle in transaction');
        expect(mine['query'], contains(_previousStatement));
        expect(mine['wait_event_type'], 'Client');
        expect(mine['wait_event'], 'ClientRead');
        expect(
          timeout.report,
          allOf(
            contains('idle in transaction'),
            contains('ClientRead'),
            contains(_previousStatement),
            contains('$pid'),
          ),
        );
        expect(timeout.toString(), contains(_previousStatement));
        expect(await backendGone(pid), isTrue);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'a statement sent to a transaction executor while its savepoint holds '
      'it fails within seconds and the stack shows both levels',
      () async {
        final connection = await openConnection();
        final pid = await backendPid(connection);
        final guard = DbWaitGuard.forTarget(target, deadline: _deadline);
        final db = TenturaDb.forTest(
          database: PgDatabase.opened(
            connection,
            enableMigrations: false,
          ).interceptWith(guard),
        );
        await db.customSelect('SELECT 1').get();
        final clock = Stopwatch()..start();

        Object? failure;
        try {
          await db
              .transaction(() async {
                final outer = db.resolvedEngine.executor;
                await db.transaction(() async {
                  await outer.runSelect(
                    'SELECT 1 AS stale_outer_wait',
                    const [],
                  );
                });
              })
              .timeout(_fewSeconds);
        } on Object catch (error) {
          failure = error;
        }

        expect(failure, isA<DbWaitTimeoutException>());
        final timeout = failure! as DbWaitTimeoutException;
        expect(clock.elapsed, lessThan(_fewSeconds));
        expect(timeout.scopeStack, hasLength(2));
        final mine = timeout.activity.singleWhere(
          (row) => row['pid'] == pid,
        );
        expect(mine['state'], 'idle in transaction');
        expect('${mine['query']}'.toUpperCase(), contains('SAVEPOINT'));
        expect(mine['wait_event'], 'ClientRead');
        expect(
          timeout.report.toUpperCase(),
          allOf(
            contains('IDLE IN TRANSACTION'),
            contains('CLIENTREAD'),
            contains('SAVEPOINT'),
            contains('$pid'),
          ),
        );
        expect(timeout.toString().toUpperCase(), contains('SAVEPOINT'));
        expect(await backendGone(pid), isTrue);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'a statement stuck on a lock in a leased scope fails past the deadline, '
      'its connection is aborted and the pool keeps serving',
      () async {
        final blocker = await openConnection();
        final blockerPid = await backendPid(blocker);
        await blocker.execute('SELECT pg_advisory_lock($_advisoryKey)');
        final db = openDisposablePgDatabase(target, waitDeadline: _deadline);
        addTearDown(db.close);
        final clock = Stopwatch()..start();

        Object? failure;
        try {
          await db
              .withConnectionScope(() async {
                // Only the guard may end this wait, whatever lock timeout the
                // database carries.
                await db.customStatement('SET lock_timeout = 0');
                return db
                    .customSelect(
                      'SELECT pg_advisory_lock($_advisoryKey) AS locked',
                    )
                    .get();
              })
              .timeout(_fewSeconds);
        } on Object catch (error) {
          failure = error;
        }

        expect(failure, isA<DbWaitTimeoutException>());
        final timeout = failure! as DbWaitTimeoutException;
        expect(clock.elapsed, lessThan(_fewSeconds));
        final waiting = timeout.activity.where(
          (row) => row['wait_event'] == 'advisory',
        );
        expect(waiting, hasLength(1));
        expect(waiting.single['state'], 'active');
        expect(waiting.single['wait_event_type'], 'Lock');
        final waitingPid = waiting.single['pid']! as int;
        expect(
          await backendGone(waitingPid),
          isTrue,
          reason: 'the leased connection that was waiting must be aborted',
        );
        expect(
          (await readDbActivity(target)).any(
            (row) => row['pid'] == blockerPid,
          ),
          isTrue,
          reason: 'only the waiting backend is aborted, not the lock holder',
        );

        await blocker.execute('SELECT pg_advisory_unlock($_advisoryKey)');
        final after = await db.customSelect('SELECT 1 AS ok').getSingle();
        expect(after.read<int>('ok'), 1);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'a statement that finishes in time is untouched by the guard',
      () async {
        final connection = await openConnection();
        final guard = DbWaitGuard.forTarget(target, deadline: _deadline);
        final db = TenturaDb.forTest(
          database: PgDatabase.opened(
            connection,
            enableMigrations: false,
          ).interceptWith(guard),
        );

        final answer = await db.transaction(() async {
          final row = await db.customSelect('SELECT 42 AS answer').getSingle();
          return row.read<int>('answer');
        });

        expect(answer, 42);
        expect(guard.activeScopeStack, isEmpty);
      },
    );
  });

  group('hang watchdog', () {
    test(
      'dumps the scope stack and backend activity once while the action is '
      'still running, then lets it finish',
      () async {
        final connection = await openConnection();
        final guard = DbWaitGuard.forTarget(
          target,
          deadline: const Duration(seconds: 30),
        );
        final db = TenturaDb.forTest(
          database: PgDatabase.opened(
            connection,
            enableMigrations: false,
          ).interceptWith(guard),
        );
        final lines = <String>[];
        final watchdog = DbHangWatchdog(
          target: target,
          dumpAfter: const Duration(seconds: 1),
          guards: [guard],
          write: lines.add,
        );

        final result = await watchdog.watch(
          () => db.transaction(() async {
            await db.customSelect("SELECT '$_previousStatement'").get();
            await Future<void>.delayed(const Duration(milliseconds: 2500));
            return 'finished';
          }),
        );

        expect(result, 'finished');
        final dump = lines.join('\n');
        expect(dump, contains('pg_stat_activity'));
        expect(dump.toLowerCase(), contains('scope stack'));
        expect(dump, contains('idle in transaction'));
        expect(dump, contains('ClientRead'));
        expect(dump, contains(_previousStatement));
        expect(
          RegExp('pg_stat_activity').allMatches(dump),
          hasLength(1),
          reason: 'one dump per guarded action',
        );
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'stays silent when the action finishes before the threshold',
      () async {
        final lines = <String>[];
        final watchdog = DbHangWatchdog(
          target: target,
          dumpAfter: const Duration(seconds: 1),
          write: lines.add,
        );

        final result = await watchdog.watch(() async => 'quick');
        await Future<void>.delayed(const Duration(milliseconds: 1500));

        expect(result, 'quick');
        expect(lines, isEmpty);
      },
    );

    test('rethrows the failure of the guarded action', () async {
      final watchdog = DbHangWatchdog(
        target: target,
        dumpAfter: const Duration(seconds: 1),
        write: (_) {},
      );

      await expectLater(
        watchdog.watch<void>(() async => throw const FormatException('boom')),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
