import 'dart:async';

import 'package:injectable/injectable.dart';

import 'package:tentura/data/model/beacon_model.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/beacon.dart';

import '../gql/_g/my_work_fetch.req.gql.dart';

/// Result of [MyWorkRepository.fetchInit] (non-closed full rows + closed id hints).
typedef MyWorkInitResult = ({
  List<Beacon> authoredNonClosed,
  List<Beacon> committedNonClosed,
  List<String> authoredClosedIds,
  List<String> committedClosedIds,
});

/// Result of [MyWorkRepository.fetchClosed] (full closed rows).
typedef MyWorkClosedResult = ({
  List<Beacon> authoredClosed,
  List<Beacon> committedClosed,
});

@lazySingleton
class MyWorkRepository {
  MyWorkRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  static const _kNetworkTimeout = Duration(seconds: 60);

  Future<MyWorkInitResult> fetchInit({
    required String userId,
    required String context,
  }) async {
    final r = await _remoteApiService
        .request(
          GMyWorkInitReq(
            (b) => b..vars.userId = userId..vars.context = context,
          ),
        )
        .timeout(_kNetworkTimeout)
        .first;
    final d = r.dataOrThrow(label: _label);
    return (
      authoredNonClosed: d.authoredNonClosed
          .map((e) => BeaconModel(e).toEntity())
          .toList(),
      committedNonClosed: d.committedNonClosed
          .map((e) => BeaconModel(e.beacon).toEntity())
          .toList(),
      authoredClosedIds: d.authoredClosedIds.map((e) => e.id).toList(),
      committedClosedIds:
          d.committedClosedIds.map((e) => e.beacon.id).toList(),
    );
  }

  Future<MyWorkClosedResult> fetchClosed({
    required String userId,
    required String context,
  }) async {
    final r = await _remoteApiService
        .request(
          GMyWorkClosedReq(
            (b) => b..vars.userId = userId..vars.context = context,
          ),
        )
        .timeout(_kNetworkTimeout)
        .first;
    final d = r.dataOrThrow(label: _label);
    return (
      authoredClosed:
          d.authoredClosed.map((e) => BeaconModel(e).toEntity()).toList(),
      committedClosed: d.committedClosed
          .map((e) => BeaconModel(e.beacon).toEntity())
          .toList(),
    );
  }

  static const _label = 'MyWork';
}
