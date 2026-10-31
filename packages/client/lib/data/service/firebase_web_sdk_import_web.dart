import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Matches `supportedFirebaseJsSdkVersion` in the pinned `firebase_core_web`
/// package (see `pubspec.lock`); keep in sync when upgrading Firebase.
const _defaultFirebaseJsSdkVersion = '12.17.0';

/// On web, `Firebase.initializeApp` loads Firebase JS via dynamic `import()`.
/// When that import is blocked, `firebase_core_web` never completes its
/// internal completer (#880) — probe the same URL first so init fails fast.
Future<void> assertFirebaseWebSdkReachable() async {
  final global = web.window as JSObject;
  if (global.getProperty('firebase_core'.toJS) != null) {
    return;
  }

  final override = global.getProperty('flutterfire_web_sdk_version'.toJS);
  final version = override != null && override.isA<JSString>()
      ? (override as JSString).toDart
      : _defaultFirebaseJsSdkVersion;
  final url = 'https://www.gstatic.com/firebasejs/$version/firebase-app.js';

  try {
    await importModule(url.toJS).toDart;
  } on Object catch (error, stackTrace) {
    Error.throwWithStackTrace(
      StateError('Firebase JS SDK import failed ($url): $error'),
      stackTrace,
    );
  }
}
