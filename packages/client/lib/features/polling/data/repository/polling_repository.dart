import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';

import '../gql/_g/polling_act.req.gql.dart';

@Singleton(env: [Environment.dev, Environment.prod])
class PollingRepository {
  static const _label = 'Polling';

  PollingRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  Future<void> vote({
    required String pollingId,
    required String variantId,
  }) => _remoteApiService
      .request(
        GPollingActReq(
          (b) => b.vars
            ..pollingId = pollingId
            ..variantId = variantId,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label).pollingAct);
}
