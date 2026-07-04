import 'package:injectable/injectable.dart';

import 'package:tentura/data/repository/remote_repository.dart';

import 'package:tentura/features/notification/data/gql/_g/fcm_register_token.req.gql.dart';
import 'package:tentura/features/notification/data/gql/_g/fcm_send_test_notification.req.gql.dart';
import 'package:tentura/features/notification/data/gql/_g/fcm_token_delete.req.gql.dart';
import 'package:tentura/features/notification/domain/entity/fcm_test_send_result.dart';
import 'package:tentura/features/notification/domain/exception.dart';
import 'package:tentura/features/notification/domain/port/fcm_remote_repository_port.dart';
import 'package:tentura/features/notification/fcm_debug_log.dart';

@Singleton(
  as: FcmRemoteRepositoryPort,
  env: [Environment.dev, Environment.prod],
)
class FcmRemoteRepository extends RemoteRepository
    implements FcmRemoteRepositoryPort {
  FcmRemoteRepository({
    required super.remoteApiService,
    required super.log,
  });

  @override
  Future<void> registerToken({
    required String appId,
    required String token,
    required String platform,
  }) async {
    fcmLog(
      'FcmRemoteRepository: fcmTokenRegister '
      'platform=$platform appId=$appId token=${fcmTokenFingerprint(token)}',
    );
    final data = await requestDataOnlineOrThrow(
      GFcmRegisterTokenReq(
        (r) => r.vars
          ..appId = appId
          ..token = token
          ..platform = platform,
      ),
      label: _label,
    );
    if (!data.fcmTokenRegister) {
      fcmLog('FcmRemoteRepository: fcmTokenRegister rejected by server');
      throw const FcmRegistrationRejectedException();
    }
    fcmLog('FcmRemoteRepository: fcmTokenRegister response OK');
  }

  @override
  Future<void> deleteToken({required String appId}) async {
    fcmLog('FcmRemoteRepository: fcmTokenDelete appId=$appId');
    await requestDataOnlineOrThrow(
      GFcmTokenDeleteReq(
        (r) => r.vars..appId = appId,
      ),
      label: _label,
    );
    fcmLog('FcmRemoteRepository: fcmTokenDelete response OK');
  }

  @override
  Future<FcmTestSendResult> sendTestNotification() async {
    final data = await requestDataOnlineOrThrow(
      GFcmSendTestNotificationReq(),
      label: _label,
    );
    final result = data.fcmSendTestNotification;
    return FcmTestSendResult(
      ok: result.ok,
      devices: result.devices,
      sent: result.sent,
      mock: result.mock,
      reason: result.reason,
    );
  }

  static const _label = 'Fcm';
}
