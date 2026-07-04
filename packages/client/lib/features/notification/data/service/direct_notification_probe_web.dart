import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Calls `ServiceWorkerRegistration.showNotification()` directly from the
/// page — no FCM, no server, no push relay involved at all. Used to isolate
/// whether a device/browser can display a notification full stop (permission
/// genuinely in effect, OS-level delivery surfaces enabled) versus whether a
/// failure is somewhere in the FCM → platform push-relay → service worker
/// chain, which produces zero visibility from our server logs (confirmed:
/// FCM's `HTTP 200` only means Google accepted the message, not that the
/// platform's push relay — e.g. Apple's, for Safari — actually delivered it).
/// See docs/qa-push-testing.md "Data-only push payloads".
Future<void> showDirectTestNotification() async {
  final registration = await web.window.navigator.serviceWorker.ready.toDart;
  await registration
      .showNotification(
        'Direct test (no push)',
        web.NotificationOptions(
          body: 'If you see this, this device can display notifications — '
              'the failure is in FCM/push delivery, not local display.',
          icon: '/icons/Icon-192.png',
        ),
      )
      .toDart;
}
