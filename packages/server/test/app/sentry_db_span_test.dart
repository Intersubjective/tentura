import 'package:sentry/sentry.dart';
import 'package:test/test.dart';

import 'package:tentura_server/app/sentry/sentry_db_span.dart';

void main() {
  group('sentryDbSpan', () {
    SentryTransaction? capturedTransaction;

    setUp(() async {
      await Sentry.close();
      capturedTransaction = null;
      await Sentry.init((options) {
        options
          ..dsn = 'https://public@o123.ingest.sentry.io/1'
            // Deliberate: rethrow exceptions in user closures during tests.
            // ignore: invalid_use_of_internal_member
            ..automatedTestMode = true
          ..tracesSampleRate = 1.0
          ..beforeSendTransaction = (transaction, hint) {
            capturedTransaction = transaction;
            return transaction;
          };
      });
    });

    tearDown(() async {
      await Sentry.close();
    });

    test('runs the body unchanged and returns its value when there is no active transaction', () async {
      expect(Sentry.getSpan(), isNull);

      var invoked = false;
      ISentrySpan? seenSpan;
      final result = await sentryDbSpan('db.fact.pin', (span) async {
        invoked = true;
        seenSpan = span;
        return 42;
      });

      expect(invoked, isTrue, reason: 'body must still run without a transaction');
      expect(result, 42);
      expect(seenSpan, isNull, reason: 'no transaction means no span to pass in');
    });

    test('opens a child span on the current transaction and finishes it with ok status', () async {
      final transaction = Sentry.startTransaction(
        'test-tx',
        'test',
        bindToScope: true,
      );

      var invoked = false;
      ISentrySpan? seenSpan;
      final result = await sentryDbSpan('db.fact.pin', (span) async {
        invoked = true;
        seenSpan = span;
        expect(span, isNotNull, reason: 'an active transaction must yield a span');
        expect(span!.finished, isFalse, reason: 'span must still be open inside the body');
        return 7;
      });

      expect(invoked, isTrue, reason: 'body must run under an active transaction too');
      expect(result, 7);
      expect(seenSpan, isNotNull);
      expect(seenSpan!.context.operation, 'db.fact.pin');
      expect(seenSpan!.context.parentSpanId, transaction.context.spanId);
      expect(seenSpan!.finished, isTrue, reason: 'span must be finished once the body returns');
      expect(seenSpan!.status, SpanStatus.ok());

      await transaction.finish();

      expect(capturedTransaction, isNotNull);
      final sentChild = capturedTransaction!.spans.singleWhere(
        (span) => span.context.operation == 'db.fact.pin',
      );
      expect(
        sentChild.status,
        SpanStatus.ok(),
        reason: 'the finished child span must be part of the sent transaction tree',
      );
    });

    test('finishes the child span with an error status and rethrows when the body throws', () async {
      final transaction = Sentry.startTransaction(
        'test-tx',
        'test',
        bindToScope: true,
      );

      var invoked = false;
      ISentrySpan? seenSpan;
      final error = StateError('boom');

      await expectLater(
        sentryDbSpan('db.fact.remove', (span) async {
          invoked = true;
          seenSpan = span;
          expect(span, isNotNull);
          throw error;
        }),
        throwsA(same(error)),
      );

      expect(invoked, isTrue, reason: 'body must run before it throws');
      expect(seenSpan, isNotNull);
      expect(seenSpan!.finished, isTrue);
      expect(seenSpan!.status, SpanStatus.internalError());
      expect(seenSpan!.throwable, same(error));

      await transaction.finish();

      expect(capturedTransaction, isNotNull);
      final sentChild = capturedTransaction!.spans.singleWhere(
        (span) => span.context.operation == 'db.fact.remove',
      );
      expect(
        sentChild.status,
        SpanStatus.internalError(),
        reason: 'the error status must survive onto the sent transaction tree',
      );
      expect(sentChild.throwable, same(error));
    });
  });
}
