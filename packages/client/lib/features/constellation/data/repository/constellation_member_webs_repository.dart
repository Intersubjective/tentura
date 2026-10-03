import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';

import '../../domain/entity/constellation_field.dart';
import '../../domain/port/constellation_member_webs_port.dart';
import '../gql/_g/beacon_member_webs.req.gql.dart';
import '../model/constellation_field_mapper.dart';

@LazySingleton(
  as: ConstellationMemberWebsPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
final class ConstellationMemberWebsRepository
    implements ConstellationMemberWebsPort {
  ConstellationMemberWebsRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  @override
  Future<List<ConstellationMemberWeb>> fetch(String beaconId) =>
      _remoteApiService
          .request(GBeaconMemberWebsReq((b) => b.vars.id = beaconId))
          .firstWhere((response) => response.dataSource == DataSource.Link)
          .then(
            (response) => mapBeaconMemberWebs(
              response.dataOrThrow(label: 'BeaconMemberWebs').beaconMemberWebs,
            ),
          );
}
