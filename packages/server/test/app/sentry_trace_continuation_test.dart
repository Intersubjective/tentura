import 'package:sentry/sentry.dart';
import 'package:test/test.dart';

import 'package:tentura_server/app/sentry/sentry_trace_propagation.dart';

void main() {
  group('parseSentryTraceHeader', () {
    test('returns null for invalid header', () {
      expect(parseSentryTraceHeader('invalid'), isNull);
    });

    test('parses valid sentry-trace header', () {
      final traceId = SentryId.newId();
      final spanId = SpanId.newId();
      final header = SentryTraceHeader(traceId, spanId, sampled: true);
      final parsed = parseSentryTraceHeader(header.value);
      expect(parsed?.traceId, traceId);
      expect(parsed?.spanId, spanId);
      expect(parsed?.sampled, isTrue);
    });
  });

  group('applyIncomingTraceToHub', () {
    late Hub hub;

    setUp(() async {
      await Sentry.close();
      await Sentry.init((options) {
        options
          ..dsn = 'https://public@o123.ingest.sentry.io/1'
          ..automatedTestMode = true
          ..tracesSampleRate = 1.0;
      });
      hub = Sentry.clone();
    });

    tearDown(() async {
      await Sentry.close();
    });

    test('continues inbound trace id and parent span on request hub', () async {
      final traceId = SentryId.newId();
      final parentSpanId = SpanId.newId();
      final traceHeader = SentryTraceHeader(traceId, parentSpanId, sampled: true);

      applyIncomingTraceToHub(hub, traceHeader, null);

      final txContext = buildHttpServerTransactionContext(
        hub: hub,
        transactionName: 'POST /api/v2/graphql',
        traceHeader: traceHeader,
      );

      final transaction = hub.startTransactionWithContext(
        txContext,
        bindToScope: true,
      );

      expect(transaction.traceContext()?.traceId, traceId);
      expect(transaction.context.parentSpanId, parentSpanId);

      await transaction.finish();
    });
  });
}
