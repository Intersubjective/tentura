import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/app/sentry/sentry_benign_filter.dart';
import 'package:tentura/data/service/remote_api_client/exception.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/domain/exception/user_input_exception.dart';
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

    test('TitleTooShortException is benign', () {
      expect(
        isBenignSentryThrowable(const TitleTooShortException()),
        isTrue,
      );
    });

    test('InvitationCodeIsWrongException is benign', () {
      expect(
        isBenignSentryThrowable(const InvitationCodeIsWrongException()),
        isTrue,
      );
    });

    test('AuthSeedIsWrongException is benign', () {
      expect(
        isBenignSentryThrowable(const AuthSeedIsWrongException()),
        isTrue,
      );
    });

    test('PollingQuestionTooShortException is benign', () {
      expect(
        isBenignSentryThrowable(const PollingQuestionTooShortException()),
        isTrue,
      );
    });

    test('SocketException message is benign', () {
      expect(
        isBenignSentryThrowable(
          Exception('SocketException: failed host lookup'),
        ),
        isTrue,
      );
    });

    test('FCM service worker registration timeout is benign', () {
      expect(
        isBenignSentryThrowable(
          Exception(
            'AbortError: Failed to register a ServiceWorker for scope '
            "('https://dev.tentura.io/firebase-cloud-messaging-push-scope') "
            "with script ('https://dev.tentura.io/firebase-messaging-sw.js'): "
            'Timed out while trying to start the Service Worker.',
          ),
        ),
        isTrue,
      );
    });

    test('Flutter web NOTICES asset load failure is benign', () {
      expect(
        isBenignSentryThrowable(
          Exception(
            'Unable to load asset: "NOTICES".\n'
            'The asset does not exist or has empty data.',
          ),
        ),
        isTrue,
      );
    });

    test('web_socket Future already completed is benign', () {
      expect(
        isBenignSentryThrowable(
          StateError('Bad state: Future already completed'),
        ),
        isTrue,
      );
    });

    test('WebSocket connection failed is benign', () {
      expect(
        isBenignSentryThrowable(
          Exception('WebSocketChannelException: WebSocket connection failed.'),
        ),
        isTrue,
      );
    });

    test('Clipboard setData failure is benign', () {
      expect(
        isBenignSentryThrowable(
          Exception(
            'PlatformException(copy_fail, Clipboard.setData failed., null, null)',
          ),
        ),
        isTrue,
      );
    });

    test('Firebase Messaging unsupported browser is benign', () {
      expect(
        isBenignSentryThrowable(
          Exception(
            "FirebaseError: Messaging: This browser doesn't support the "
            "API's required to use the Firebase SDK. "
            '(messaging/unsupported-browser).',
          ),
        ),
        isTrue,
      );
    });
  });

  group('isBenignSentryExceptionText', () {
    test('FCM service worker registration timeout is benign', () {
      expect(
        isBenignSentryExceptionText(
          'AbortError: Failed to register a ServiceWorker for scope '
          "('https://dev.tentura.io/firebase-cloud-messaging-push-scope') "
          "with script ('https://dev.tentura.io/firebase-messaging-sw.js'): "
          'Timed out while trying to start the Service Worker.',
        ),
        isTrue,
      );
    });
  });
}
