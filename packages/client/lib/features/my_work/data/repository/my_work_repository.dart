import 'dart:async';

import 'package:injectable/injectable.dart';

import 'package:tentura/data/model/beacon_model.dart';
import 'package:tentura/data/model/user_model.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';

import '../../domain/entity/my_work_fetch_types.dart';
import '../gql/_g/my_work_fetch.data.gql.dart';
import '../gql/_g/my_work_fetch.req.gql.dart';

export '../../domain/entity/my_work_fetch_types.dart'
    show MyWorkClosedResult, MyWorkHelpOfferedRow, MyWorkInitResult;

@Singleton(env: [Environment.dev, Environment.prod])
class MyWorkRepository {
  MyWorkRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  static const _kNetworkTimeout = Duration(seconds: 60);

  Future<MyWorkInitResult> fetchInit({required String userId}) async {
    final r = await _remoteApiService
        .request(
          GMyWorkInitReq((b) => b..vars.userId = userId),
        )
        .timeout(_kNetworkTimeout)
        .first;
    final d = r.dataOrThrow(label: _label);
    return (
      authoredNonClosed: d.authoredNonClosed
          .map((e) => BeaconModel(e).toEntity())
          .toList(),
      helpOfferedNonClosed:
          d.helpOfferedNonClosed.map(_mapInitHelpOfferedRow).toList(),
      authoredClosedIds: d.authoredClosedIds.map((e) => e.id).toList(),
      helpOfferedClosedIds:
          d.helpOfferedClosedIds.map((e) => e.beacon.id).toList(),
    );
  }

  Future<MyWorkClosedResult> fetchClosed({required String userId}) async {
    final r = await _remoteApiService
        .request(
          GMyWorkClosedReq((b) => b..vars.userId = userId),
        )
        .timeout(_kNetworkTimeout)
        .first;
    final d = r.dataOrThrow(label: _label);
    return (
      authoredClosed:
          d.authoredClosed.map((e) => BeaconModel(e).toEntity()).toList(),
      helpOfferedClosed:
          d.helpOfferedClosed.map(_mapClosedHelpOfferedRow).toList(),
    );
  }

  static MyWorkHelpOfferedRow _mapInitHelpOfferedRow(
    GMyWorkInitData_helpOfferedNonClosed e,
  ) {
    final b = e.beacon;
    final beacon = BeaconModel(b).toEntity();
    final forwarders = b.forward_edges
        .map((fe) => UserModel(fe.sender).toEntity())
        .toList();
    return (
      beacon: beacon,
      offerHelpMessage: e.message,
      helpType: e.help_type,
      authorResponseType: CoordinationResponseType.tryFromInt(
        e.coordination?.response_type,
      ),
      forwarderSenders: forwarders,
      helpOfferRowUpdatedAt: e.updated_at,
      authorCoordinationUpdatedAt: e.coordination?.updated_at,
    );
  }

  static MyWorkHelpOfferedRow _mapClosedHelpOfferedRow(
    GMyWorkClosedData_helpOfferedClosed e,
  ) {
    final b = e.beacon;
    final beacon = BeaconModel(b).toEntity();
    final forwarders = b.forward_edges
        .map((fe) => UserModel(fe.sender).toEntity())
        .toList();
    return (
      beacon: beacon,
      offerHelpMessage: e.message,
      helpType: e.help_type,
      authorResponseType: CoordinationResponseType.tryFromInt(
        e.coordination?.response_type,
      ),
      forwarderSenders: forwarders,
      helpOfferRowUpdatedAt: e.updated_at,
      authorCoordinationUpdatedAt: e.coordination?.updated_at,
    );
  }

  static const _label = 'MyWork';
}
