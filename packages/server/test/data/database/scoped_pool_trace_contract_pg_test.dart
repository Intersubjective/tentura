@Tags(['pg', 'multi-connection'])
library;

import 'dart:async';

import 'package:injectable/injectable.dart' show Environment;
import 'package:sentry/sentry.dart';
import 'package:test/test.dart';
import 'package:tentura_server/data/database/main_db_pool.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_wait.dart';
import '../../support/sentry_trace_capture.dart';

const _acquireOp = 'db.pool.acquire';
const _drainOp = 'db.cancel.drain';
const _transactionOp = 'db.transaction';
const _sqlOp = 'db.sql';
const _queryCanceled = '57014';

Matcher _serverErrorWithCode(String sqlState) => isA<ServerException>().having(
  (error) => error.code,
  'SQLSTATE',
  sqlState,
);

/// Tracing, pool-acquire and cancellation-drain behavior of a [TenturaDb]
/// scoped over a [MainDbPool], the shape DI gives every repository.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_SCOPED_POOL_TRACE_TEST_DB',
    defaultNamePrefix: 'tentura_test_scoped_pool_trace',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }

  late DisposablePgWriterSession session;
  final capture = SentryTraceCapture();

  MainDbPool openPool(int maxConnectionCount) {
    final db = target.databaseEnv;
    final pool = MainDbPool(
      Env(
        environment: Environment.test,
        printEnv: false,
        isDebugModeOn: false,
        pgHost: db.pgHost,
        pgPort: db.pgPort,
        pgDatabase: db.pgDatabase,
        pgUsername: db.pgUsername,
        pgPassword: db.pgPassword,
        maxConnectionCount: maxConnectionCount,
      ),
    );
    addTearDown(pool.close);
    return pool;
  }

  TenturaDb scoped(MainDbPool pool) {
    final db = TenturaDb.scoped(pool);
    addTearDown(db.close);
    return db;
  }

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
  });
  tearDownAll(() => tearDownDisposablePgWriter(session: session));
  setUp(capture.start);
  tearDown(capture.stop);

  group('Scoped main database tracing', () {
    test(
      'a transaction shows its pool acquire before its SQL and is tagged '
      'with the backend PID it ran on',
      () async {
        final request = capture.beginRequest();
        final db = scoped(openPool(2));

        final pid = await db.transaction(() async {
          final row = await db
              .customSelect('SELECT pg_backend_pid() AS pid')
              .getSingle();
          return row.read<int>('pid');
        });

        final sent = await capture.finish(request);
        final transaction = sent.spansWithOperation(_transactionOp).single;
        expect(transaction.tags['db.backend_pid'], '$pid');
        final acquire = sent
            .spansWithOperation(_acquireOp)
            .singleWhere(
              (s) => s.context.parentSpanId == transaction.context.spanId,
            );
        expect(acquire.finished, isTrue);
        expect(acquire.status, const SpanStatus.ok());
        expect(acquire.isWithin(transaction), isTrue);
        final statements = sent
            .spansWithOperation(_sqlOp)
            .where((s) => s.context.parentSpanId == transaction.context.spanId);
        expect(statements, isNotEmpty);
        for (final statement in statements) {
          expect(acquire.endsBeforeStartOf(statement), isTrue);
        }
      },
    );

    test(
      'a transaction queued behind a busy single-connection pool shows the '
      'wait as its own pool acquire time, not as SQL time',
      () async {
        final request = capture.beginRequest();
        final pool = openPool(1);
        final holderDb = scoped(pool);
        final waiterDb = scoped(pool);

        final holderHasConnection = Completer<void>();
        final release = Completer<void>();
        final holder = holderDb.transaction(() async {
          await holderDb.customSelect('SELECT 1 AS held').get();
          holderHasConnection.complete();
          await release.future;
        });
        await holderHasConnection.future;
        final waiter = waiterDb.transaction(
          () => waiterDb.customSelect('SELECT 1 AS quick').get(),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final releasedAt = DateTime.now().toUtc();
        release.complete();
        await Future.wait([holder, waiter]).timeout(kCompletionWait);

        final sent = await capture.finish(request);
        final quick = sent
            .spansWithOperation(_sqlOp)
            .singleWhere(
              (s) => (s.context.description ?? '').contains('quick'),
            );
        final waiterTransaction = sent.spanWithId(quick.context.parentSpanId!);
        final acquire = sent
            .spansWithOperation(_acquireOp)
            .singleWhere(
              (s) => s.context.parentSpanId == waiterTransaction.context.spanId,
            );
        expect(
          acquire.startTimestamp.isBefore(releasedAt),
          isTrue,
          reason: 'the acquire span opens while the pool is still busy',
        );
        expect(
          acquire.endTimestamp!.isBefore(releasedAt),
          isFalse,
          reason: 'and stays open until the holder releases the connection',
        );
        expect(
          acquire.endTimestamp!.difference(acquire.startTimestamp),
          greaterThanOrEqualTo(const Duration(milliseconds: 40)),
          reason: 'the queued wait is accounted to the acquire span',
        );
        expect(acquire.endsBeforeStartOf(quick), isTrue);
      },
    );

    test('database work outside any Sentry transaction still works', () async {
      expect(Sentry.getSpan(), isNull);
      final db = scoped(openPool(2));
      final rows = await db.transaction(
        () => db.customSelect('SELECT 1 AS one').get(),
      );
      expect(rows.single.read<int>('one'), 1);
    });
  });

  group('Scoped main database cancellation drain', () {
    test(
      'a statement cancelled by the server is drained inside its transaction '
      'before the single pooled connection is reused',
      () async {
        final request = capture.beginRequest();
        final db = scoped(openPool(1));

        await expectLater(
          db.transaction(() async {
            await db.customStatement("SET LOCAL statement_timeout = '50ms'");
            await db.customSelect('SELECT pg_sleep(10) AS slept').get();
          }),
          throwsA(_serverErrorWithCode(_queryCanceled)),
        );
        final next = await db.transaction(
          () => db.customSelect('SELECT 1 AS reused').getSingle(),
        );
        expect(next.read<int>('reused'), 1);

        final sent = await capture.finish(request);
        final transactions = sent.spansWithOperation(_transactionOp)
          ..sort((a, b) => a.startTimestamp.compareTo(b.startTimestamp));
        expect(transactions, hasLength(2));
        final (cancelled, reused) = (transactions.first, transactions.last);
        expect(cancelled.status, isNot(const SpanStatus.ok()));
        expect(reused.status, const SpanStatus.ok());

        final drain = sent.spansWithOperation(_drainOp).single;
        expect(drain.context.parentSpanId, cancelled.context.spanId);
        expect(drain.finished, isTrue);
        expect(drain.status, const SpanStatus.ok());
        expect(drain.isWithin(cancelled), isTrue);
        final slept = sent
            .spansWithOperation(_sqlOp)
            .singleWhere(
              (s) => (s.context.description ?? '').contains('slept'),
            );
        expect(slept.status, isNot(const SpanStatus.ok()));
        expect(
          slept.endsBeforeStartOf(drain),
          isTrue,
          reason: 'draining starts once the cancelled statement has failed',
        );
        expect(cancelled.endsBeforeStartOf(reused), isTrue);
      },
      timeout: const Timeout(kCompletionWait),
    );

    test(
      'a statement that fails without being cancelled rolls back with no '
      'drain span',
      () async {
        final request = capture.beginRequest();
        final db = scoped(openPool(1));

        await expectLater(
          db.transaction(() async {
            await db.customStatement(
              'CREATE TEMP TABLE drain_probe (id int PRIMARY KEY)',
            );
            await db.customStatement(
              'INSERT INTO drain_probe (id) VALUES (1), (1)',
            );
          }),
          throwsA(_serverErrorWithCode('23505')),
        );

        final sent = await capture.finish(request);
        final transaction = sent.spansWithOperation(_transactionOp).single;
        expect(transaction.status, isNot(const SpanStatus.ok()));
        expect(sent.spansWithOperation(_drainOp), isEmpty);
      },
    );

    test(
      'a transaction that completes normally records no drain span',
      () async {
        final request = capture.beginRequest();
        final db = scoped(openPool(2));

        await db.transaction(() => db.customSelect('SELECT 1 AS one').get());

        final sent = await capture.finish(request);
        expect(sent.spansWithOperation(_transactionOp), hasLength(1));
        expect(sent.spansWithOperation(_drainOp), isEmpty);
      },
    );
  });

  group('Auth database isolation from scoped main database', () {
    test(
      'session traffic runs on its own pool and is not queued behind a main '
      'database holding its only connection',
      () async {
        final db = target.databaseEnv;
        final env = Env(
          environment: Environment.test,
          printEnv: false,
          isDebugModeOn: false,
          pgHost: db.pgHost,
          pgPort: db.pgPort,
          pgDatabase: db.pgDatabase,
          pgUsername: db.pgUsername,
          pgPassword: db.pgPassword,
          maxConnectionCount: 1,
        );
        final mainPool = MainDbPool(env);
        addTearDown(mainPool.close);
        final mainDb = scoped(mainPool);
        final authDb = TenturaDb.auth(env);
        addTearDown(authDb.close);

        final holderHasConnection = Completer<int>();
        final release = Completer<void>();
        final holder = mainDb.transaction(() async {
          final row = await mainDb
              .customSelect('SELECT pg_backend_pid() AS pid')
              .getSingle();
          holderHasConnection.complete(row.read<int>('pid'));
          await release.future;
        });
        final mainPid = await holderHasConnection.future;

        final authRow = await authDb
            .customSelect('SELECT pg_backend_pid() AS pid')
            .getSingle()
            .timeout(const Duration(seconds: 5));
        release.complete();
        await holder;

        expect(authRow.read<int>('pid'), isNot(mainPid));
      },
    );
  });
}
