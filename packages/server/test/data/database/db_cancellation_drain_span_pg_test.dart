@Tags(['pg'])
library;

import 'package:sentry/sentry.dart';
import 'package:test/test.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;

import '../../support/disposable_pg_target.dart';
import '../../support/pg_wait.dart';
import '../../support/sentry_trace_capture.dart';
import '../../support/transaction_pinned_pool_env.dart';

const _drainOp = 'db.cancel.drain';
const _transactionOp = 'db.transaction';
const _sqlOp = 'db.sql';
const _queryCanceled = '57014';
const _uniqueViolation = '23505';

Matcher _serverErrorWithCode(String sqlState) => isA<ServerException>().having(
  (error) => error.code,
  'SQLSTATE',
  sqlState,
);

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_DB_CANCEL_DRAIN_TEST_DB',
    defaultNamePrefix: 'tentura_test_cancel_drain',
  );
  final pgUnavailableReason = await pgSkipReason(target);
  final skipReason = pgUnavailableReason ?? false;
  DisposablePgWriterSession? session;
  final capture = SentryTraceCapture();

  group('Cancellation drain span', () {
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
        'a statement cancelled by the server is followed by a drain span '
        'inside its transaction, before the connection is reused '
        '(${enabled ? 'per-transaction lease' : 'pinned session'})',
        () async {
          final request = capture.beginRequest();
          final db = TenturaDb(
            transactionPinnedPoolEnv(
              enabled: enabled,
              maxConnectionCount: 1,
              postgres: target.databaseEnv,
            ),
          );
          addTearDown(db.close);

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

          final drains = sent.spansWithOperation(_drainOp);
          expect(drains, hasLength(1), reason: 'only the cancelled work drains');
          final drain = drains.single;
          expect(drain.context.parentSpanId, cancelled.context.spanId);
          expect(drain.finished, isTrue);
          expect(drain.status, const SpanStatus.ok());
          expect(drain.isWithin(cancelled), isTrue);

          final slept = sent
              .spansWithOperation(_sqlOp)
              .singleWhere((s) => (s.context.description ?? '').contains('slept'));
          expect(slept.status, isNot(const SpanStatus.ok()));
          expect(
            slept.endsBeforeStartOf(drain),
            isTrue,
            reason: 'draining starts once the cancelled statement has failed',
          );
          expect(
            cancelled.endsBeforeStartOf(reused),
            isTrue,
            reason: 'the next transaction starts only after the drain',
          );
        },
        skip: skipReason,
        timeout: const Timeout(kCompletionWait),
      );
    }

    for (final enabled in [false, true]) {
      test(
        'a statement that fails without being cancelled rolls back with no '
        'drain span (${enabled ? 'per-transaction lease' : 'pinned session'})',
        () async {
          final request = capture.beginRequest();
          final db = TenturaDb(
            transactionPinnedPoolEnv(
              enabled: enabled,
              maxConnectionCount: 1,
              postgres: target.databaseEnv,
            ),
          );
          addTearDown(db.close);

          await expectLater(
            db.transaction(() async {
              await db.customStatement(
                'CREATE TEMP TABLE drain_probe (id int PRIMARY KEY)',
              );
              await db.customStatement(
                'INSERT INTO drain_probe (id) VALUES (1), (1)',
              );
            }),
            throwsA(_serverErrorWithCode(_uniqueViolation)),
          );

          final sent = await capture.finish(request);
          final transaction = sent.spansWithOperation(_transactionOp).single;
          expect(transaction.status, isNot(const SpanStatus.ok()));
          expect(
            sent.spansWithOperation(_drainOp),
            isEmpty,
            reason: 'only a cancelled statement needs its connection drained',
          );
        },
        skip: skipReason,
        timeout: const Timeout(kCompletionWait),
      );
    }

    test(
      'a transaction that completes normally records no drain span',
      () async {
        final request = capture.beginRequest();
        final db = TenturaDb(
          transactionPinnedPoolEnv(enabled: true, postgres: target.databaseEnv),
        );
        addTearDown(db.close);

        await db.transaction(() => db.customSelect('SELECT 1 AS one').get());

        final sent = await capture.finish(request);
        expect(sent.spansWithOperation(_transactionOp), hasLength(1));
        expect(sent.spansWithOperation(_drainOp), isEmpty);
      },
      skip: skipReason,
    );
  });
}
