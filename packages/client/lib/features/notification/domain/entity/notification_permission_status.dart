/// Where this device stands on notification permission, read without
/// prompting.
enum NotificationPermissionStatus {
  /// The person allowed notifications.
  granted,

  /// The person blocked notifications; only the browser or OS settings can
  /// change that now.
  denied,

  /// Nobody has asked yet (the browser's `default`). Asking must come from a
  /// user gesture, so the app offers the in-app prompt instead of asking on
  /// load.
  notDetermined,

  /// Push is not available here (unsupported browser, or Firebase not
  /// configured). Nothing to ask for.
  unsupported,
}
