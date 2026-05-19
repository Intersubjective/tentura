import 'package:injectable/injectable.dart';

import 'package:tentura/data/repository/remote_repository.dart';

import 'package:tentura/features/notification/data/gql/_g/fcm_register_token.req.gql.dart';
import 'package:tentura/features/notification/data/gql/_g/fcm_token_delete.req.gql.dart';
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
    await requestDataOnlineOrThrow(
      GFcmRegisterTokenReq(
        (r) => r.vars
          ..appId = appId
          ..token = token
          ..platform = platform,
      ),
      label: _label,
    );
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

  static const _label = 'Fcm';
}
