import 'package:injectable/injectable.dart';

import 'package:tentura/data/model/beacon_model.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/beacon.dart';

import '../gql/_g/my_work_fetch.req.gql.dart';

@lazySingleton
class MyWorkRepository {
  MyWorkRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  Future<List<Beacon>> fetchAuthored({
    required String userId,
    required String context,
  }) => _remoteApiService
      .request(
        GMyWorkAuthoredReq(
          (r) => r..vars.userId = userId..vars.context = context,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label).beacon)
      .then(
        (v) => v.map((e) => (e as BeaconModel).toEntity()).toList(),
      );

  Future<List<Beacon>> fetchCommitted({
    required String userId,
    required String context,
  }) => _remoteApiService
      .request(
        GMyWorkCommittedReq(
          (r) => r..vars.userId = userId..vars.context = context,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label).beacon_commitment)
      .then(
        (v) => v
            .map((e) => (e.beacon as BeaconModel).toEntity())
            .toList(),
      );

  static const _label = 'MyWork';
}
