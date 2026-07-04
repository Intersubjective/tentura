import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/fcm_message_entity.dart';
import 'package:tentura_server/domain/entity/fcm_token_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/fcm_token_repository_port.dart';
import 'package:tentura_server/env.dart';
import 'package:tentura_server/data/repository/fcm_remote_repository.dart';
import 'package:tentura_server/data/service/fcm_service.dart';

/// Per-message failures (a rejected token, an unexpected error) must not
/// abort delivery to the rest of the batch — only a genuinely bad access
/// token ([FcmUnauthorizedException]) should. Regression coverage for the
/// THIRD_PARTY_AUTH_ERROR bug: it used to come back as an HTTP 401, get
/// classified the same as a bad access token, and abort sending to every
/// other device in the same batch.
void main() {
  FcmRemoteRepository buildRepo(FakeFcmService fcmService) => FcmRemoteRepository(
    Env(fbProjectId: 'test', fbAccessTokenExpiresIn: const Duration(hours: 1)),
    fcmService,
    FakeFcmTokenRepository(),
    Logger('test'),
  );

  test(
    'FcmMessageRejectedException for one token does not abort the rest '
    'of the batch',
    () async {
      final fcmService = FakeFcmService({
        'firefox-token': const FcmMessageRejectedException(
          token: 'firefox-token',
          errorCode: 'THIRD_PARTY_AUTH_ERROR',
        ),
      });
      final repo = buildRepo(fcmService);

      final results = await repo.sendChatNotification(
        fcmTokens: ['firefox-token', 'chrome-token'],
        message: const FcmNotificationEntity(title: 't', body: 'b'),
      );

      expect(fcmService.attempted, ['firefox-token', 'chrome-token']);
      expect(results, hasLength(1));
      expect(results.single, isA<FcmMessageRejectedException>());
      expect(
        (results.single as FcmMessageRejectedException).errorCode,
        'THIRD_PARTY_AUTH_ERROR',
      );
    },
  );

  test('an unexpected exception for one token does not abort the batch', () async {
    final fcmService = FakeFcmService({
      'broken-token': Exception('boom'),
    });
    final repo = buildRepo(fcmService);

    final results = await repo.sendChatNotification(
      fcmTokens: ['broken-token', 'chrome-token'],
      message: const FcmNotificationEntity(title: 't', body: 'b'),
    );

    expect(fcmService.attempted, ['broken-token', 'chrome-token']);
    expect(results, hasLength(1));
  });

  test('FcmUnauthorizedException aborts the rest of the batch', () async {
    final fcmService = FakeFcmService({
      'first-token': const FcmUnauthorizedException(),
    });
    final repo = buildRepo(fcmService);

    await expectLater(
      repo.sendChatNotification(
        fcmTokens: ['first-token', 'second-token'],
        message: const FcmNotificationEntity(title: 't', body: 'b'),
      ),
      throwsA(isA<FcmUnauthorizedException>()),
    );

    // Never reached the second token — the batch stopped at the first error.
    expect(fcmService.attempted, ['first-token']);
  });
}

class FakeFcmService extends FcmService {
  FakeFcmService(this.throwsByToken) : super(Env(fbProjectId: 'test'));

  final Map<String, Exception> throwsByToken;
  final attempted = <String>[];

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
    attempted.add(fcmToken);
    final error = throwsByToken[fcmToken];
    if (error != null) {
      throw error;
    }
  }
}

class FakeFcmTokenRepository implements FcmTokenRepositoryPort {
  @override
  Future<void> deleteByUserAndApp({
    required String userId,
    required String appId,
  }) async {}

  @override
  Future<void> deleteToken(String token) async {}

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
