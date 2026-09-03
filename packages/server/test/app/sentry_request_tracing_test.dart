import 'package:sentry/sentry.dart';
import 'package:shelf/shelf.dart' show HijackException;
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/app/sentry/sentry_request_tracing.dart';
import 'package:tentura_server/consts.dart';
import 'package:tentura_server/env.dart';

void main() {
  group('sentryShouldTraceRequest', () {
    test('excludes WebSocket, health, and graphiql paths', () {
      expect(
        sentryShouldTraceRequest(
          Request('GET', Uri.parse('http://localhost$kPathWebSocketEndpoint')),
        ),
        isFalse,
      );
      expect(
        sentryShouldTraceRequest(
          Request('GET', Uri.parse('http://localhost/health')),
        ),
        isFalse,
      );
      expect(
        sentryShouldTraceRequest(
          Request('GET', Uri.parse('http://localhost/graphiql')),
        ),
        isFalse,
      );
    });

    test('traces other API paths', () {
      expect(
        sentryShouldTraceRequest(
          Request('GET', Uri.parse('http://localhost/api/v2/session')),
        ),
        isTrue,
      );
    });
  });

  group('sentryRequestTracing', () {
    late List<SentryEvent> capturedEvents;
    SentryTransaction? capturedTransaction;

    setUp(() async {
      await Sentry.close();
      capturedEvents = [];
      capturedTransaction = null;
      await Sentry.init((options) {
        options
          ..dsn = 'https://public@o123.ingest.sentry.io/1'
          ..automatedTestMode = true
          ..tracesSampleRate = 1.0
          ..beforeSend = (event, hint) {
            capturedEvents.add(event);
            return event;
          }
          ..beforeSendTransaction = (transaction, hint) {
            capturedTransaction = transaction;
            return transaction;
          };
      });
    });

    tearDown(() async {
      await Sentry.close();
    });

    test('HijackException on traced path does not capture and finishes ok', () async {
      final env = Env(sentryDsn: 'https://public@o123.ingest.sentry.io/1');
      final middleware = sentryRequestTracing(env: env);
      final handler = middleware((request) async {
        throw const HijackException();
      });

      await expectLater(
        handler(Request('GET', Uri.parse('http://localhost/api/v2/session'))),
        throwsA(isA<HijackException>()),
      );

      expect(capturedEvents, isEmpty);
      expect(capturedTransaction?.contexts.trace?.status, SpanStatus.ok());
    });
  });
}
