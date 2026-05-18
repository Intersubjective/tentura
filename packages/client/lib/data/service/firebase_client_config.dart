import 'package:tentura/env.dart';

import 'package:tentura/features/notification/fcm_debug_log.dart';

/// Firebase web app id format: `1:<projectNumber>:web:<hash>` (android/ios differ).
bool looksLikeFirebaseAppId(String value) {
  if (value.isEmpty) {
    return false;
  }
  final parts = value.split(':');
  if (parts.length < 4 || parts[0] != '1') {
    return false;
  }
  final platform = parts[2];
  return platform == 'web' || platform == 'android' || platform == 'ios';
}

bool looksLikeFirebaseApiKey(String value) =>
    value.startsWith('AIza') && !value.contains(':');

/// Compile-time [Env] has enough valid Firebase fields for FCM on this client.
bool isFirebaseClientConfigValid(Env env) {
  if (env.firebaseApiKey.isEmpty) {
    return false;
  }
  if (env.firebaseAppId.isEmpty) {
    return false;
  }
  if (looksLikeFirebaseApiKey(env.firebaseAppId)) {
    return false;
  }
  if (!looksLikeFirebaseAppId(env.firebaseAppId)) {
    return false;
  }
  if (env.firebaseProjectId.isEmpty || env.firebaseMessagingSenderId.isEmpty) {
    return false;
  }
  return true;
}

String? firebaseClientConfigIssue(Env env) {
  if (env.firebaseApiKey.isEmpty) {
    return null;
  }
  if (env.firebaseAppId.isEmpty) {
    return 'FB_APP_ID is empty (set in --dart-define-from-file / CLIENT_DART_DEFINES)';
  }
  if (looksLikeFirebaseApiKey(env.firebaseAppId)) {
    return 'FB_APP_ID looks like FB_API_KEY — use Firebase Console Web App ID '
        '(1:…:web:…), not the API key';
  }
  if (!looksLikeFirebaseAppId(env.firebaseAppId)) {
    return 'FB_APP_ID format invalid (expected 1:<number>:web|android|ios:<hash>)';
  }
  if (env.firebaseProjectId.isEmpty) {
    return 'FB_PROJECT_ID is empty';
  }
  if (env.firebaseMessagingSenderId.isEmpty) {
    return 'FB_SENDER_ID is empty';
  }
  return null;
}

void logFirebaseClientConfig(Env env) {
  final issue = firebaseClientConfigIssue(env);
  if (issue != null) {
    fcmLog('Firebase client config invalid: $issue');
    return;
  }
  if (env.firebaseApiKey.isEmpty) {
    fcmLog('Firebase client config: disabled (FB_API_KEY empty)');
    return;
  }
  final appId = env.firebaseAppId;
  final maskedAppId = appId.length > 16
      ? '${appId.substring(0, 12)}…${appId.substring(appId.length - 6)}'
      : appId;
  fcmLog(
    'Firebase client config OK '
    'projectId=${env.firebaseProjectId} '
    'appId=$maskedAppId '
    'vapidKeySet=${env.firebaseVapidKey.isNotEmpty}',
  );
}
