import 'package:sentry/sentry.dart';
import 'package:test/test.dart';
import 'package:tentura_server/data/database/postgres_serialization_retry.dart';

import '../../support/sentry_trace_capture.dart';

const _backoff = 'db.retry.backoff';
const _slept = Duration(milliseconds: 40);

Future<void> _sleep(Duration _) => Future<void>.delayed(_slept);

void main() {
  final capture = SentryTraceCapture();

  setUp(capture.start);
  tearDown(capture.stop);

  group('Bounded retry backoff span', () {
    test('each sleep between attempts is its own span covering the time '
        'actually slept', () async {
      final request = capture.beginRequest();
      var calls = 0;

      final result = await withPostgresBoundedRetry(
        () async {
          if (++calls < 3) {
            throw const PostgresSnapshotUnavailableException('retry me');
          }
          return 'done';
        },
        sleep: _sleep,
      );

      expect(result, 'done');
      final sent = await capture.finish(request);
      final spans = sent.spansWithOperation(_backoff);
      expect(spans, hasLength(2));
      for (final span in spans) {
        expect(span.context.parentSpanId, request.context.spanId);
        expect(span.status, const SpanStatus.ok());
        expect(
          span.elapsed,
          greaterThanOrEqualTo(_slept - const Duration(milliseconds: 10)),
          reason: 'backoff time must be visible apart from SQL time',
        );
      }
    });

    test('an attempt that succeeds first time records no backoff span', () async {
      final request = capture.beginRequest();

      await withPostgresBoundedRetry(() async => 1, sleep: _sleep);

      final sent = await capture.finish(request);
      expect(sent.spansWithOperation(_backoff), isEmpty);
    });

    test('a retry loop outside any Sentry transaction still retries', () async {
      expect(Sentry.getSpan(), isNull);
      var calls = 0;
      final result = await withPostgresBoundedRetry(
        () async {
          if (++calls < 2) {
            throw const PostgresSnapshotUnavailableException('retry me');
          }
          return calls;
        },
        sleep: (_) async {},
      );
      expect(result, 2);
    });
  });
}
