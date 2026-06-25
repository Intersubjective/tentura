import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/app/sentry/sentry_benign_filter.dart';
import 'package:tentura/data/service/remote_api_client/exception.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/features/auth/domain/exception.dart';

void main() {
  group('isBenignSentryThrowable', () {
    test('ConnectionUplinkException is benign', () {
      expect(
        isBenignSentryThrowable(const ConnectionUplinkException()),
        isTrue,
      );
    });

    test('AuthSessionLostException is benign', () {
      expect(
        isBenignSentryThrowable(const AuthSessionLostException()),
        isTrue,
      );
    });

    test('AuthenticationNoKeyException is benign', () {
      expect(
        isBenignSentryThrowable(const AuthenticationNoKeyException()),
        isTrue,
      );
    });

    test('RemoteApiException is not benign', () {
      expect(
        isBenignSentryThrowable(const RemoteApiException('server said no')),
        isFalse,
      );
    });

    test('SocketException message is benign', () {
      expect(
        isBenignSentryThrowable(Exception('SocketException: failed host lookup')),
        isTrue,
      );
    });
  });

  group('isBenignSentryLogRecord', () {
    test('severe log with benign error is skipped', () {
      final record = LogRecord(
        Level.SEVERE,
        'remote failure',
        'TestLogger',
        const ConnectionUplinkException(),
      );
      expect(isBenignSentryLogRecord(record), isTrue);
    });

    test('severe log with RemoteApiException is reported', () {
      final record = LogRecord(
        Level.SEVERE,
        'remote failure',
        'TestLogger',
        const RemoteApiException('bad request'),
      );
      expect(isBenignSentryLogRecord(record), isFalse);
    });

    test('severe log with auth-no-key message is skipped', () {
      final record = LogRecord(
        Level.SEVERE,
        'Key pair is not set.',
        'TestLogger',
      );
      expect(isBenignSentryLogRecord(record), isTrue);
    });
  });
}
