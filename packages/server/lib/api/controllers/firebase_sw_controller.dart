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

messaging.onBackgroundMessage((message) => {
  console.log("onBackgroundMessage", message);
  navigator.setAppBadge();
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
