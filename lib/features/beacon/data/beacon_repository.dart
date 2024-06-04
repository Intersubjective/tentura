import 'package:latlong2/latlong.dart' show LatLng;
import 'package:flutter/material.dart' show DateTimeRange;

import 'package:tentura/data/gql/gql_client.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/geo.dart';

import 'gql/_g/beacon_create.req.gql.dart';
import 'gql/_g/beacon_delete_by_id.req.gql.dart';
import 'gql/_g/beacon_update_by_id.req.gql.dart';
import 'gql/_g/beacons_fetch_by_user_id.req.gql.dart';

export 'package:tentura/data/gql/gql_client.dart';

class BeaconRepository {
  static const _label = 'Beacon';

  BeaconRepository({
    required this.userId,
    required this.gqlClient,
  });

  final String userId;
  final Client gqlClient;

  late final _fetchRequest = GBeaconsFetchByUserIdReq(
    (b) => b
      ..fetchPolicy = FetchPolicy.CacheAndNetwork
      ..vars.user_id = userId,
  );

  Stream<Iterable<Beacon>> get stream => gqlClient
      .request(_fetchRequest)
      .map((r) => r.dataOrThrow(label: _label).beacon.map((r) => r as Beacon));

  void refetch() => gqlClient.requestController.add(_fetchRequest);

  Future<Beacon> create({
    required String title,
    bool hasPicture = false,
    String description = '',
    DateTimeRange? dateRange,
    Coordinates? coordinates,
  }) =>
      gqlClient
          .request(
            GBeaconCreateReq(
              (b) => b.vars
                ..title = title
                ..description = description
                ..has_picture = hasPicture
                ..timerange = dateRange
                ..place = coordinates == null
                    ? null
                    : LatLng(coordinates.lat, coordinates.long),
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then(
            (r) => r.dataOrThrow(label: _label).insert_beacon_one! as Beacon,
          );

  Future<void> delete(String id) => gqlClient
      .request(GBeaconDeleteByIdReq((b) => b.vars.id = id))
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label));

  Future<Beacon> setEnabled({
    required String id,
    required bool isEnabled,
  }) =>
      gqlClient
          .request(GBeaconUpdateByIdReq(
            (b) => b
              ..vars.id = id
              ..vars.enabled = isEnabled,
          ))
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) => r.dataOrThrow().update_beacon_by_pk! as Beacon);
}
