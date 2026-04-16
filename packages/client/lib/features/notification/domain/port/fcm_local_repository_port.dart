import 'dart:async';

import '../entity/notification_permissions.dart';

abstract class FcmLocalRepositoryPort {
  Stream<String> get onTokenRefresh;

  Future<String?> getToken();

  Future<NotificationPermissions> requestPermission();
}
