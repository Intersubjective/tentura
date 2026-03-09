import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/fcm_token_entity.dart';

import '../fcm_token_repository.dart';

@Injectable(
  as: FcmTokenRepository,
  env: [Environment.test],
  order: 1,
)
class FcmTokenRepositoryMock implements FcmTokenRepository {
  @override
  Future<Iterable<FcmTokenEntity>> getTokensByUserId(String userId) async => [];
  @override
  Future<void> putToken({
    required String userId,
    required String appId,
    required String token,
    required String platform,
  }) => Future.value();

  @override
  Future<void> deleteToken(String token) async {}
}
