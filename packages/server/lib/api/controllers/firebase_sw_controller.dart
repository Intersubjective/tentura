import 'package:crypto/crypto.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts.dart';

import '_base_controller.dart';
import 'push_action_controller.dart';

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
// Plan pushes (#220 §5.9) carry buttons: `data.actions` is a JSON list of
// {id, title}, `data.actionToken` a short-lived signed token. Buttons only
// show where the browser supports them (Chromium: Notification.maxActions);
// elsewhere a tap opens the step, which is the fallback anyway.
function planActions(data) {
  try {
    const max = (self.Notification && self.Notification.maxActions) || 0;
    if (max <= 0 || !data.actions || !data.actionToken) return [];
    const parsed = JSON.parse(data.actions);
    if (!Array.isArray(parsed)) return [];
    return parsed
      .filter((a) => a && a.id && a.title)
      .slice(0, max)
      .map((a) => ({ action: String(a.id), title: String(a.title) }));
  } catch (e) {
    return [];
  }
}

messaging.onBackgroundMessage(async (payload) => {
  try {
    const data = payload.data || {};
    if (navigator.setAppBadge) {
      navigator.setAppBadge().catch(() => {});
    }
    const actions = planActions(data);
    const options = {
      body: data.body || "",
      icon: "$kPathWebAppIcon192",
      tag: data.tag || data.beaconId || undefined,
      data: {
        link: data.link || "/",
        actionToken: actions.length > 0 ? data.actionToken : undefined,
        doneText: data.actionDoneText || "",
        ackText: data.actionAckText || "",
        failedText: data.actionFailedText || "",
        title: data.title || "Tentura",
      },
    };
    if (actions.length > 0) {
      options.actions = actions;
      // Re-alert when a newer push replaces the same step's notification.
      options.renotify = true;
    }
    await self.registration.showNotification(data.title || "Tentura", options);
  } catch (e) {
    console.error("onBackgroundMessage failed", e);
  }
});

function openLink(link) {
  return clients.matchAll({ type: "window", includeUncontrolled: true }).then((windowClients) => {
    for (const client of windowClients) {
      if (client.url === link && "focus" in client) {
        return client.focus();
      }
    }
    if (clients.openWindow) {
      return clients.openWindow(link);
    }
  });
}

// A plan button ("done" / "ack") posts the signed token to
// ${PushActionController.path} and replaces the notification with the
// outcome; "open" and a tap on the body open the link (the step's card).
async function runPlanAction(notification, action) {
  const data = notification.data || {};
  const tag = notification.tag || undefined;
  let ok = false;
  try {
    const response = await fetch("${PushActionController.path}", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ token: data.actionToken }),
      credentials: "omit",
    });
    ok = response.ok;
  } catch (e) {
    ok = false;
  }
  const done = action === "ack" ? data.ackText : data.doneText;
  await self.registration.showNotification(data.title || "Tentura", {
    body: (ok ? done : data.failedText) || "",
    icon: "$kPathWebAppIcon192",
    tag: tag,
    data: { link: data.link || "/" },
  });
}

// Data-only messages skip FCM's automatic click-to-open handling too, so we
// own that as well: focus an existing tab on the link if one is open,
// otherwise open a new one.
self.addEventListener("notificationclick", (event) => {
  const notification = event.notification;
  notification.close();
  const data = notification.data || {};
  const link = data.link || "/";
  const action = event.action || "";
  if ((action === "done" || action === "ack") && data.actionToken) {
    event.waitUntil(runPlanAction(notification, action));
    return;
  }
  event.waitUntil(openLink(link));
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
