import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/firebase_sw_controller.dart';
import 'package:tentura_server/env.dart';

/// Regression coverage for the Safari quirk documented in
/// docs/qa-push-testing.md "Data-only push payloads": Safari cancels a web
/// push subscription outright if a push event arrives and the service
/// worker doesn't end up calling showNotification() for it. These assertions
/// exist so that "simplifying" the generated service worker back to relying
/// on Firebase's automatic notification display fails a test, not just a
/// code comment.
void main() {
  Request request() =>
      Request('GET', Uri.parse('http://localhost/firebase-messaging-sw.js'));

  test('generated service worker always displays its own notification', () async {
    final controller = FirebaseSwController(
      Env(
        fbApiKey: 'test-api-key',
        fbAppId: '1:123:web:abc',
        fbProjectId: 'tentura-test',
        fbAuthDomain: 'tentura-test.firebaseapp.com',
        fbStorageBucket: 'tentura-test.appspot.com',
        fbSenderId: '123',
      ),
    );

    final body = await controller.handler(request()).then(
          (r) => r.readAsString(),
        );

    expect(body, contains('onBackgroundMessage'));
    expect(body, contains('showNotification'));
    expect(body, contains('notificationclick'));
  });

  test('falls back to a no-op stub when FB_API_KEY is unset', () async {
    final controller = FirebaseSwController(Env(fbApiKey: ''));

    final body = await controller.handler(request()).then(
          (r) => r.readAsString(),
        );

    expect(body, isNot(contains('firebase.initializeApp')));
    expect(body, isNot(contains('onBackgroundMessage')));
  });
}
