import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/port/fcm_token_repository_port.dart';

import '_use_case_base.dart';

@Injectable(order: 2)
final class FcmCase extends UseCaseBase {
  FcmCase(
    this._fcmTokenRepository, {
    required super.env,
    required super.logger,
  });

  final FcmTokenRepositoryPort _fcmTokenRepository;

  Future<bool> registerToken({
    required String userId,
    required String appId,
    required String token,
    required String platform,
  }) async {
    if (userId.isEmpty || appId.isEmpty || token.isEmpty || platform.isEmpty) {
      return false;
    }
    try {
      await _fcmTokenRepository.putToken(
        userId: userId,
        appId: appId,
        token: token,
        platform: platform,
      );
      logger.info(
        '[FCM] fcmTokenRegister stored userId=$userId platform=$platform '
        'appId=$appId tokenLen=${token.length}',
      );
      return true;
    } catch (e, st) {
      logger.warning('[FCM] fcmTokenRegister failed userId=$userId: $e', e, st);
      return false;
    }
  }
}
