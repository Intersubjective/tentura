import '../../domain/entity/notification_permission_status.dart';

/// Always null (unknown) on non-web platforms — there's no browser
/// Notification API to cross-check against.
bool? browserNotificationPermissionGranted() => null;

/// Always null on non-web platforms: ask the plugin instead.
NotificationPermissionStatus? browserNotificationPermissionStatus() => null;
