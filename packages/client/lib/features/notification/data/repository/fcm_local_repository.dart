import 'package:injectable/injectable.dart';

import '../../domain/entity/notification_permissions.dart';
import '../../domain/port/fcm_local_repository_port.dart';
import '../service/fcm_service.dart';

@Singleton(
  as: FcmLocalRepositoryPort,
  env: [Environment.dev, Environment.prod],
)
class FcmLocalRepository implements FcmLocalRepositoryPort {
  FcmLocalRepository(this._fcmService);

  final FcmService _fcmService;

  @override
  Stream<String> get onTokenRefresh => _fcmService.onTokenRefresh;

  //
  @override
  Future<String?> getToken() => _fcmService.getToken();

  //
  @override
  Future<NotificationPermissions> requestPermission() =>
      _fcmService.requestPermission();
}
