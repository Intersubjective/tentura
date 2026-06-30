import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/app/sentry/report_sentry_message.dart';

void main() {
  test('benign message is skipped without requiring initialized Sentry', () {
    expect(
      () => reportSentryMessage(
        'AbortError: Failed to register a ServiceWorker with script '
        'firebase-messaging-sw.js: Timed out while trying to start the '
        'Service Worker.',
      ),
      returnsNormally,
    );
  });
}
