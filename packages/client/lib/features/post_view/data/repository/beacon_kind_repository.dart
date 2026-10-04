import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/features/beacon/domain/exception.dart';

import '../gql/_g/beacon_kind_fetch.req.gql.dart';

/// Resolves `beacon.kind` so the route can pick the Request or Post screen.
/// A beacon's kind never changes, so answers are cached per id.
@lazySingleton
class BeaconKindRepository {
  BeaconKindRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  final _kinds = <String, BeaconKind>{};

  Future<BeaconKind> fetchKind(String beaconId) async {
    final cached = _kinds[beaconId];
    if (cached != null) return cached;
    final row = await _remoteApiService
        .request(GBeaconKindFetchReq((b) => b.vars.id = beaconId))
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: 'BeaconKindFetch').beacon_by_pk);
    if (row == null) throw BeaconFetchException(beaconId);
    return _kinds[beaconId] = BeaconKind.fromValue(row.kind);
  }
}
