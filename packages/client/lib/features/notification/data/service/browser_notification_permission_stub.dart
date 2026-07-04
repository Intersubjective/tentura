/// Always null (unknown) on non-web platforms — there's no browser
/// Notification API to cross-check against.
bool? browserNotificationPermissionGranted() => null;
