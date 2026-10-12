@Tags(['pg'])
library;

import 'dart:async';

import 'package:sentry/sentry.dart';
import 'package:test/test.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;

import '../../support/disposable_pg_target.dart';
import '../../support/pg_wait.dart';
import '../../support/sentry_trace_capture.dart';
import '../../support/transaction_pinned_pool_env.dart';

const _acquireOp = 'db.pool.acquire';
const _transactionOp = 'db.transaction';
const _sqlOp = 'db.sql';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_DB_POOL_SPANS_TEST_DB',
    defaultNamePrefix: 'tentura_test_pool_spans',
  );
  final pgUnavailableReason = await pgSkipReason(target);
  final skipReason = pgUnavailableReason ?? false;
  DisposablePgWriterSession? session;
  final capture = SentryTraceCapture();

  group('Database pool acquire spans', () {
    setUpAll(() async {
      if (pgUnavailableReason != null) return;
      session = await setUpDisposablePgWriter(target: target);
    });

    tearDownAll(() async {
      if (session case final opened?) {
        await tearDownDisposablePgWriter(session: opened);
      }
    });

    setUp(capture.start);
    tearDown(capture.stop);

    for (final enabled in [false, true]) {
      test(
        'one transaction shows its pool acquire and tags the transaction '
        'span with the backend PID it ran on '
        '(${enabled ? 'per-transaction lease' : 'pinned session'})',
        () async {
          final request = capture.beginRequest();
          final db = TenturaDb(
            transactionPinnedPoolEnv(enabled: enabled, postgres: target.databaseEnv),
          );
          addTearDown(db.close);

          final pid = await db.transaction(() async {
            final row = await db
                .customSelect('SELECT pg_backend_pid() AS pid')
                .getSingle();
            return row.read<int>('pid');
          });

          final sent = await capture.finish(request);
          final transaction = sent.spansWithOperation(_transactionOp).single;
          expect(transaction.tags['db.backend_pid'], '$pid');
          final acquires = sent
              .spansWithOperation(_acquireOp)
              .where((s) => s.context.parentSpanId == transaction.context.spanId);
          expect(
            acquires,
            hasLength(1),
            reason: 'the transaction span owns the acquire of its connection',
          );
          final acquire = acquires.single;
          expect(acquire.finished, isTrue);
          expect(acquire.status, const SpanStatus.ok());
          expect(acquire.isWithin(transaction), isTrue);
          final statements = sent
              .spansWithOperation(_sqlOp)
              .where((s) => s.context.parentSpanId == transaction.context.spanId);
          expect(statements, isNotEmpty);
          for (final statement in statements) {
            expect(
              acquire.endsBeforeStartOf(statement),
              isTrue,
              reason: 'acquire time is not folded into SQL time',
            );
          }
        },
        skip: skipReason,
      );
    }

    for (final enabled in [false, true]) {
      test(
        'concurrent traced transactions leave each one free to set its '
        'isolation level first '
        '(${enabled ? 'per-transaction lease' : 'pinned session'})',
        () async {
          final request = capture.beginRequest();
          final db = TenturaDb(
            transactionPinnedPoolEnv(
              enabled: enabled,
              postgres: target.databaseEnv,
            ),
          );
          addTearDown(db.close);

          // The backend PID probe of one transaction must not run on the
          // connection another has begun: Postgres rejects SET TRANSACTION
          // ISOLATION LEVEL (25001) after any query of the transaction.
          // Staggered, so later ones arrive while earlier ones are mid-flight.
          final running = <Future<void>>[];
          for (var i = 0; i < 40; i++) {
            running.add(
              db.withReadSnapshot(
                () => db.customSelect('SELECT $i AS n').get(),
              ),
            );
            await Future<void>.delayed(const Duration(milliseconds: 1));
          }
          await Future.wait(running).timeout(kCompletionWait);

          final sent = await capture.finish(request);
          expect(sent.spansWithOperation(_transactionOp), hasLength(40));
        },
        skip: skipReason,
      );
    }

    test(
      'a transaction queued for a busy pool shows the wait as pool acquire '
      'time of that transaction, separate from its SQL time',
      () async {
        final request = capture.beginRequest();
        final db = TenturaDb(
          transactionPinnedPoolEnv(
            enabled: true,
            maxConnectionCount: 1,
            postgres: target.databaseEnv,
          ),
        );
        addTearDown(db.close);
        await db.customSelect('SELECT 1').get();

        final holderHasConnection = Completer<void>();
        final release = Completer<void>();
        final holder = db.transaction(() async {
          await db.customSelect('SELECT 1 AS held').get();
          holderHasConnection.complete();
          await release.future;
        });
        await holderHasConnection.future;
        final waiter = db.transaction(
          () => db.customSelect('SELECT 1 AS quick').get(),
        );
        // The only connection is held until `release`, so the waiter cannot
        // acquire before then.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final releasedAt = DateTime.now().toUtc();
        release.complete();
        await Future.wait([holder, waiter]).timeout(kCompletionWait);

        final sent = await capture.finish(request);
        final quick = sent
            .spansWithOperation(_sqlOp)
            .singleWhere((s) => (s.context.description ?? '').contains('quick'));
        final waiterTransaction = sent.spanWithId(quick.context.parentSpanId!);
        expect(waiterTransaction.context.operation, _transactionOp);
        final acquire = sent
            .spansWithOperation(_acquireOp)
            .singleWhere(
              (s) =>
                  s.context.parentSpanId == waiterTransaction.context.spanId,
            );
        expect(
          acquire.endTimestamp!.isBefore(releasedAt),
          isFalse,
          reason: 'the queued transaction waited for the holder to release',
        );
        expect(
          acquire.endsBeforeStartOf(quick),
          isTrue,
          reason: 'its own SQL started after the wait; the wait is not '
              'charged to it',
        );
      },
      skip: skipReason,
    );

    test('database work outside any Sentry transaction still works', () async {
      expect(Sentry.getSpan(), isNull);
      final db = TenturaDb(
        transactionPinnedPoolEnv(enabled: true, postgres: target.databaseEnv),
      );
      addTearDown(db.close);
      final rows = await db.transaction(
        () => db.customSelect('SELECT 1 AS one').get(),
      );
      expect(rows, hasLength(1));
    }, skip: skipReason);
  });
}
