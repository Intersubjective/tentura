import 'package:injectable/injectable.dart';

import 'package:tentura_server/data/repository/fcm_token_repository.dart';

@Injectable(order: 2)
class FcmCase {
  FcmCase(this._fcmTokenRepository);

  final FcmTokenRepository _fcmTokenRepository;

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
      return true;
    } catch (e) {
      print(e);
      return false;
    }
  }
}
