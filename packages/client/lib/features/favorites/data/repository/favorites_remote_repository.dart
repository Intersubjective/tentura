import 'dart:async';
import 'package:injectable/injectable.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/data/model/beacon_model.dart';
import 'package:tentura/data/repository/remote_repository.dart';

import '../../domain/exception.dart';
import '../gql/_g/beacon_fetch_pinned.req.gql.dart';
import '../gql/_g/beacon_pin_by_id.req.gql.dart';
import '../gql/_g/beacon_unpin_by_id.req.gql.dart';

@Singleton(env: [Environment.dev, Environment.prod])
class FavoritesRemoteRepository extends RemoteRepository {
  FavoritesRemoteRepository({
    required super.remoteApiService,
    required super.log,
  });

  final _controller = StreamController<Beacon>.broadcast();

  Stream<Beacon> get changes => _controller.stream;

  @disposeMethod
  Future<void> dispose() => _controller.close();

  Future<Iterable<Beacon>> fetch() async {
    final data = await requestDataOnlineOrThrow(
      GBeaconFetchPinnedReq(),
      label: _label,
    );
    return data.beacon_pinned.map((e) => (e.beacon as BeaconModel).toEntity());
  }

  Future<void> pin(Beacon beacon) async {
    final data = await requestDataOnlineOrThrow(
      GBeaconPinByIdReq((b) => b.vars.beacon_id = beacon.id),
      label: _label,
    );
    final response = data.insert_beacon_pinned_one;
    if (response == null) throw const FavoritesPinException();
    _controller.add(beacon.copyWith(isPinned: true));
  }

  Future<void> unpin({
    required String userId,
    required Beacon beacon,
  }) async {
    final data = await requestDataOnlineOrThrow(
      GBeaconUnpinByIdReq(
        (b) => b.vars
          ..user_id = userId
          ..beacon_id = beacon.id,
      ),
      label: _label,
    );
    final response = data.delete_beacon_pinned_by_pk;
    if (response == null) throw const FavoritesUnpinException();
    _controller.add(beacon.copyWith(isPinned: false));
  }

  static const _label = 'Favorites';
}
