import 'package:tentura_server/domain/entity/fcm_token_entity.dart';

abstract class FcmTokenRepositoryPort {
  Future<Iterable<FcmTokenEntity>> getTokensByUserId(String userId);

  Future<void> putToken({
    required String userId,
    required String appId,
    required String token,
    required String platform,
  });

  Future<void> deleteToken(String token);
}
