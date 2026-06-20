import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';

import '../gql/_g/beacon_archive.req.gql.dart';
import '../gql/_g/beacon_unarchive.req.gql.dart';

@Singleton(env: [Environment.dev, Environment.prod])
class ArchiveRepository {
  ArchiveRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  static const _label = 'ArchiveRepository';

  Future<void> archive(String beaconId) async {
    await _remoteApiService
        .request(GBeaconArchiveReq((b) => b.vars.beaconId = beaconId))
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label));
  }

  Future<void> unarchive({
    required String beaconId,
    required String userId,
  }) async {
    await _remoteApiService
        .request(
          GBeaconUnarchiveReq(
            (b) => b.vars
              ..beaconId = beaconId
              ..userId = userId,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label));
  }
}
