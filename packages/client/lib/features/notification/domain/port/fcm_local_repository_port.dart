import 'dart:async';

import '../entity/notification_permission_status.dart';
import '../entity/notification_permissions.dart';

abstract class FcmLocalRepositoryPort {
  Stream<String> get onTokenRefresh;

  Future<String?> getToken();

  Future<NotificationPermissions> requestPermission();

  /// Reads the current permission without showing any system prompt.
  Future<NotificationPermissionStatus> permissionStatus();
}
