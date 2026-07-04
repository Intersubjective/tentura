import 'package:web/web.dart' as web;

/// Reads `Notification.permission` straight from the browser, bypassing
/// firebase_messaging's own interpretation entirely.
///
/// See `FcmService.requestPermission` for why this exists: on an iOS Safari
/// PWA, `FirebaseMessaging.instance.requestPermission()` was observed
/// reporting `denied` while the browser's actual `Notification.permission`
/// was `granted` — confirmed live, since a direct `showNotification()` call
/// (see `direct_notification_probe_web.dart`) displayed correctly on the
/// same device at the same time this reported denied.
bool? browserNotificationPermissionGranted() {
  final permission = web.Notification.permission;
  return switch (permission) {
    'granted' => true,
    'denied' => false,
    _ => null,
  };
}
