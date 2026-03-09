import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';

import 'package:tentura/features/notification/data/gql/_g/fcm_register_token.req.gql.dart';

@singleton
class FcmRemoteRepository {
  FcmRemoteRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  Future<void> registerToken({
    required String appId,
    required String token,
    required String platform,
  }) => _remoteApiService
      .request(
        GFcmRegisterTokenReq(
          (r) => r.vars
            ..appId = appId
            ..token = token
            ..platform = platform,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label).fcmTokenRegister);

  static const _label = 'Fcm';
}
