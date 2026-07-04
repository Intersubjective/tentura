import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/fcm_message_entity.dart';
import 'package:tentura_server/domain/entity/fcm_token_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/fcm_token_repository_port.dart';
import 'package:tentura_server/env.dart';
import 'package:tentura_server/data/repository/fcm_remote_repository.dart';
import 'package:tentura_server/data/service/fcm_service.dart';

void main() {
  test('sendChatNotification prunes token on FcmTokenNotFoundException', () async {
    final tokenRepo = FakeFcmTokenRepository();
    final fcmService = FakeFcmService();
    final repo = FcmRemoteRepository(
      Env(fbProjectId: 'test', fbAccessTokenExpiresIn: const Duration(hours: 1)),
      fcmService,
      tokenRepo,
      Logger('test'),
    );

    const deadToken = 'dead-token';
    final results = await repo.sendChatNotification(
      fcmTokens: [deadToken],
      message: const FcmNotificationEntity(
        title: 't',
        body: 'b',
      ),
    );

    expect(results, hasLength(1));
    expect(results.first, isA<FcmTokenNotFoundException>());
    expect(tokenRepo.deletedTokens, [deadToken]);
  });
}

class FakeFcmService extends FcmService {
  FakeFcmService() : super(Env(fbProjectId: 'test'));

  @override
  Future<String> generateAccessToken() async => 'oauth-token';

  @override
  Future<void> sendFcmMessage({
    required String fcmToken,
    required String accessToken,
    required FcmNotificationEntity message,
    String? analyticsLabel,
    int ttlInSeconds = 0,
  }) async {
    throw FcmTokenNotFoundException(
      token: fcmToken,
      description: 'NotRegistered',
    );
  }
}

class FakeFcmTokenRepository implements FcmTokenRepositoryPort {
  final deletedTokens = <String>[];

  @override
  Future<void> deleteByUserAndApp({
    required String userId,
    required String appId,
  }) async {}

  @override
  Future<void> deleteToken(String token) async {
    deletedTokens.add(token);
  }

  @override
  Future<Iterable<FcmTokenEntity>> getTokensByUserId(String userId) async => [];

  @override
  Future<void> putToken({
    required String userId,
    required String appId,
    required String token,
    required String platform,
  }) async {}
}
