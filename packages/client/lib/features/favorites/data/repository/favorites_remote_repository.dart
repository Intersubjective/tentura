import 'dart:async';
import 'package:injectable/injectable.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/data/model/beacon_model.dart';
import 'package:tentura/data/service/remote_api_service.dart';

import '../../domain/exception.dart';
import '../gql/_g/beacon_fetch_pinned.req.gql.dart';
import '../gql/_g/beacon_pin_by_id.req.gql.dart';
import '../gql/_g/beacon_unpin_by_id.req.gql.dart';

@lazySingleton
class FavoritesRemoteRepository {
  FavoritesRemoteRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  final _controller = StreamController<Beacon>.broadcast();

  Stream<Beacon> get changes => _controller.stream;

  @disposeMethod
  Future<void> dispose() => _controller.close();

  Future<Iterable<Beacon>> fetch() => _remoteApiService
      .request(GBeaconFetchPinnedReq())
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label).beacon_pinned)
      .then((v) => v.map((e) => (e.beacon as BeaconModel).toEntity()));

  Future<void> pin(Beacon beacon) async {
    final response = await _remoteApiService
        .request(GBeaconPinByIdReq((b) => b.vars.beacon_id = beacon.id))
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).insert_beacon_pinned_one);
    if (response == null) throw const FavoritesPinException();
    _controller.add(beacon.copyWith(isPinned: true));
  }

  Future<void> unpin({
    required String userId,
    required Beacon beacon,
  }) async {
    final response = await _remoteApiService
        .request(
          GBeaconUnpinByIdReq(
            (b) => b.vars
              ..user_id = userId
              ..beacon_id = beacon.id,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).delete_beacon_pinned_by_pk);
    if (response == null) throw const FavoritesUnpinException();
    _controller.add(beacon.copyWith(isPinned: false));
  }

  static const _label = 'Favorites';
}
