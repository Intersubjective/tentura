import 'package:test/test.dart';

import 'package:tentura_server/data/database/postgres_serialization_retry.dart';

Future<void> main() async {
  group('withPostgresDeadlockOrSerializationRetry', () {
    test('succeeds on first attempt without retry', () async {
      var calls = 0;
      final result = await withPostgresDeadlockOrSerializationRetry(() async {
        calls++;
        return 7;
      }, isRetryable: (_) => true);
      expect(result, 7);
      expect(calls, 1);
    });

    test(
      'invokes action twice when first attempt throws retryable error',
      () async {
        var calls = 0;
        final result = await withPostgresDeadlockOrSerializationRetry(
          () async {
            calls++;
            if (calls == 1) {
              throw _RetryableFailure();
            }
            return 'ok';
          },
          isRetryable: (e) => e is _RetryableFailure,
        );
        expect(result, 'ok');
        expect(calls, 2);
      },
    );

    test('retry exhaustion rethrows without a third attempt', () async {
      var calls = 0;
      await expectLater(
        withPostgresDeadlockOrSerializationRetry(
          () async {
            calls++;
            throw _RetryableFailure();
          },
          isRetryable: (e) => e is _RetryableFailure,
        ),
        throwsA(isA<_RetryableFailure>()),
      );
      expect(calls, 2);
    });

    test('does not retry non-retryable errors', () async {
      var calls = 0;
      await expectLater(
        withPostgresDeadlockOrSerializationRetry(
          () async {
            calls++;
            throw StateError('fatal');
          },
          isRetryable: (e) => e is _RetryableFailure,
        ),
        throwsA(isA<StateError>()),
      );
      expect(calls, 1);
    });

    test('maxRetries zero disables retry', () async {
      var calls = 0;
      await expectLater(
        withPostgresDeadlockOrSerializationRetry(
          () async {
            calls++;
            throw _RetryableFailure();
          },
          maxRetries: 0,
          isRetryable: (e) => e is _RetryableFailure,
        ),
        throwsA(isA<_RetryableFailure>()),
      );
      expect(calls, 1);
    });
  });
}

class _RetryableFailure implements Exception {}
