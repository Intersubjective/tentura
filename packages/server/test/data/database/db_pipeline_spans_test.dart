import 'dart:isolate';

import 'package:sentry/sentry.dart';
import 'package:test/test.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;

import '../../support/sentry_trace_capture.dart';
import '../../support/transaction_statement_recorder.dart';

const _transactionOp = 'db.transaction';
const _sqlOp = 'db.sql';
const _secretArgument = 'secret-argument-value';

TenturaDb _db() {
  final database = TenturaDb.forTest(
    database: TransactionStatementRecorder(select: (sql, arguments) => [
      {'a': 1},
    ]),
  );
  addTearDown(database.close);
  return database;
}

void main() {
  final capture = SentryTraceCapture();

  setUp(capture.start);
  tearDown(capture.stop);

  group('Database pipeline spans', () {
    test('a transaction is one span covering BEGIN to COMMIT with every '
        'statement as its own child span', () async {
      final request = capture.beginRequest();
      final db = _db();

      await db.transaction(() async {
        await db.customSelect('SELECT 1 AS a').get();
        await db.customStatement(
          r'UPDATE public.probe SET note = $1',
          [_secretArgument],
        );
      });

      final sent = await capture.finish(request);
      final transactions = sent.spansWithOperation(_transactionOp);
      expect(transactions, hasLength(1));
      final transaction = transactions.single;
      expect(transaction.context.parentSpanId, request.context.spanId);
      expect(transaction.status, const SpanStatus.ok());

      final statements = sent.spansWithOperation(_sqlOp);
      final selects = statements.where(
        (s) => (s.context.description ?? '').contains('SELECT 1'),
      );
      final updates = statements.where(
        (s) => (s.context.description ?? '').contains('UPDATE public.probe'),
      );
      expect(selects, hasLength(1));
      expect(updates, hasLength(1));
      for (final statement in [...selects, ...updates]) {
        expect(
          statement.context.parentSpanId,
          transaction.context.spanId,
          reason: 'SQL inside a transaction nests under its lifetime span',
        );
        expect(statement.isWithin(transaction), isTrue);
      }
    });

    // An added privacy guard, not derived from the observability criteria:
    // bound parameters can hold user content or credentials.
    test('statement spans carry the SQL text but never bound argument '
        'values', () async {
      final request = capture.beginRequest();
      final db = _db();

      await db.transaction(
        () => db.customStatement(
          r'UPDATE public.probe SET note = $1',
          [_secretArgument],
        ),
      );

      final sent = await capture.finish(request);
      final everything = [
        for (final span in sent.spans) ...[
          span.context.description ?? '',
          '${span.data}',
          '${span.tags}',
        ],
      ].join('\n');
      expect(everything, contains('UPDATE public.probe'));
      expect(everything, isNot(contains(_secretArgument)));
    });

    test('a statement outside any transaction is a SQL span directly under '
        'the request', () async {
      final request = capture.beginRequest();
      final db = _db();

      await db.customSelect('SELECT 1 AS a').get();

      final sent = await capture.finish(request);
      expect(sent.spansWithOperation(_transactionOp), isEmpty);
      final statements = sent.spansWithOperation(_sqlOp);
      expect(statements, hasLength(1));
      expect(statements.single.context.parentSpanId, request.context.spanId);
    });

    test('a rolled-back transaction span ends with an error status and '
        'the error', () async {
      final request = capture.beginRequest();
      final db = _db();
      final failure = StateError('abort');

      await expectLater(
        db.transaction(() async {
          await db.customSelect('SELECT 1 AS a').get();
          throw failure;
        }),
        throwsA(same(failure)),
      );

      final sent = await capture.finish(request);
      final transaction = sent.spansWithOperation(_transactionOp).single;
      expect(transaction.finished, isTrue);
      expect(transaction.status, isNot(const SpanStatus.ok()));
      expect(transaction.throwable, same(failure));
      expect(
        sent.spansWithOperation('db.cancel.drain'),
        isEmpty,
        reason: 'an ordinary rollback is not a cancellation',
      );
    });

    test('transaction spans are tagged with the GraphQL operation and the '
        'isolate that ran them', () async {
      final request = capture.beginRequest(graphqlOperation: 'ConstellationFull');
      final db = _db();

      await db.withMutatingUser('actor', () async {
        await db.customSelect('SELECT 1 AS a').get();
      });

      final sent = await capture.finish(request);
      final transaction = sent.spansWithOperation(_transactionOp).first;
      expect(transaction.tags['graphql.operation'], 'ConstellationFull');
      final isolate = transaction.tags['isolate'];
      expect(isolate, isNotNull, reason: 'the isolate must be tagged');
      expect(isolate, isNotEmpty);
      if (Isolate.current.debugName case final name?) {
        expect(isolate, name);
      }
    });

    test('database work outside any Sentry transaction runs unchanged', () async {
      expect(Sentry.getSpan(), isNull);
      final db = _db();

      final rows = await db.transaction(
        () => db.customSelect('SELECT 1 AS a').get(),
      );

      expect(rows, hasLength(1));
    });
  });
}
