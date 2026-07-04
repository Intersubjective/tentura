import 'package:crypto/crypto.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts.dart';

import '_base_controller.dart';

@Injectable(order: 3)
final class FirebaseSwController extends BaseController {
  FirebaseSwController(super.env);

  late final _firebaseSwJs =
      '''
importScripts("https://www.gstatic.com/firebasejs/11.9.1/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/11.9.1/firebase-messaging-compat.js");

firebase.initializeApp({
  appId: "${env.fbAppId}",
  apiKey: "${env.fbApiKey}",
  projectId: "${env.fbProjectId}",
  authDomain: "${env.fbAuthDomain}",
  storageBucket: "${env.fbStorageBucket}",
  messagingSenderId: "${env.fbSenderId}",
});

const messaging = firebase.messaging();

// The server sends data-only messages (no top-level "notification" field —
// see buildFcmMessagePayload in fcm_service.dart for the full story), so
// THIS handler is the only thing that displays anything, on every browser.
// Do not "simplify" this back to relying on FCM's automatic notification
// display:
//  1. It gives us one consistent, explicit notification (icon, tag,
//     click-navigation) across every browser instead of each one's
//     inconsistent automatic default for a "notification"-shaped payload.
//     (An earlier theory here was that Safari also cancels a subscription
//     outright if a push arrives with nothing shown, and that this was why
//     an iOS PWA received nothing at all — that theory was wrong. The real
//     cause of that specific failure was iOS 16.x shipping web push
//     disabled by default behind Settings -> Safari -> Advanced -> Feature
//     Flags -> Notifications, fixed by Apple's iOS 17 default; confirmed
//     2026-07-05. This file is kept data-only regardless, on its own
//     merits, not because it was "the" iOS fix.)
//  2. If a "notification" field is ever added back to the payload
//     alongside this explicit showNotification() call, Chrome/Firefox show
//     BOTH their own automatic one AND ours — every push becomes a
//     duplicate (see firebase/firebase-js-sdk issues #4412, #5516, #6670).
// Keep this defensive: a thrown error here fails with nothing surfaced to
// us (no Sentry, no test suite reaches this file — it only runs inside a
// real browser's service worker).
messaging.onBackgroundMessage(async (payload) => {
  try {
    const data = payload.data || {};
    if (navigator.setAppBadge) {
      navigator.setAppBadge().catch(() => {});
    }
    await self.registration.showNotification(data.title || "Tentura", {
      body: data.body || "",
      icon: "/icons/Icon-192.png",
      tag: data.beaconId || undefined,
      data: { link: data.link || "/" },
    });
  } catch (e) {
    console.error("onBackgroundMessage failed", e);
  }
});

// Data-only messages skip FCM's automatic click-to-open handling too, so we
// own that as well: focus an existing tab on the link if one is open,
// otherwise open a new one.
self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const link = (event.notification.data && event.notification.data.link) || "/";
  event.waitUntil(
    clients.matchAll({ type: "window", includeUncontrolled: true }).then((windowClients) => {
      for (const client of windowClients) {
        if (client.url === link && "focus" in client) {
          return client.focus();
        }
      }
      if (clients.openWindow) {
        return clients.openWindow(link);
      }
    })
  );
});
''';

  late final _headers = {
    kHeaderContentType: kContentApplicationJavaScript,
    kHeaderEtag: md5.convert(_firebaseSwJs.codeUnits).toString(),
  };

  static const _firebaseSwDisabledJs = '''
self.addEventListener('install', (event) => {
  event.waitUntil(self.skipWaiting());
});
self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});
''';

  @override
  Future<Response> handler(Request request) async => env.fbApiKey.isEmpty
      ? Response.ok(
          _firebaseSwDisabledJs,
          headers: {
            kHeaderContentType: kContentApplicationJavaScript,
          },
        )
      : Response.ok(
          _firebaseSwJs,
          headers: _headers,
        );
}
