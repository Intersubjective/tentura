import '../entity/fcm_test_send_result.dart';

abstract class FcmRemoteRepositoryPort {
  Future<void> registerToken({
    required String appId,
    required String token,
    required String platform,
  });

  Future<void> deleteToken({required String appId});

  Future<FcmTestSendResult> sendTestNotification();
}
