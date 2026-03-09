import 'package:injectable/injectable.dart';

import '../../domain/entity/notification_permissions.dart';
import '../service/fcm_service.dart';

@singleton
class FcmLocalRepository {
  FcmLocalRepository(this._fcmService);

  final FcmService _fcmService;

  Stream<String> get onTokenRefresh => _fcmService.onTokenRefresh;

  //
  Future<String?> getToken() => _fcmService.getToken();

  //
  Future<NotificationPermissions> requestPermission() =>
      _fcmService.requestPermission();
}
