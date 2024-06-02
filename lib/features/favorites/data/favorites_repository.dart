import 'package:tentura/data/gql/gql_client.dart';

import 'package:tentura/domain/entity/beacon.dart';

import 'gql/_g/beacon_fetch_pinned_by_user_id.req.gql.dart';
import 'gql/_g/beacon_pin_by_id.req.gql.dart';
import 'gql/_g/beacon_unpin_by_id.req.gql.dart';

export 'package:tentura/data/gql/gql_client.dart';

class FavoritesRepository {
  static const _label = 'Favorites';

  FavoritesRepository({
    required this.gqlClient,
  });

  final Client gqlClient;

  Future<Iterable<Beacon>> fetchPinned(String userId) => gqlClient
      .request(GBeaconFetchPinnedByUserIdReq((r) => r.vars.user_id = userId))
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) => r
            .dataOrThrow(label: _label)
            .beacon_pinned
            .map((r) => r.beacon as Beacon),
      );

  Future<Beacon> pin(String id) => gqlClient
      .request(GBeaconPinByIdReq((b) => b.vars.beacon_id = id))
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) => r.dataOrThrow(label: _label).insert_beacon_pinned_one!.beacon
            as Beacon,
      );

  Future<Beacon> unpin({
    required String userId,
    required String beaconId,
  }) =>
      gqlClient
          .request(GBeaconUnpinByIdReq(
            (b) => b.vars
              ..user_id = userId
              ..beacon_id = beaconId,
          ))
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then(
            (r) => r
                .dataOrThrow(label: _label)
                .delete_beacon_pinned_by_pk!
                .beacon as Beacon,
          );
}