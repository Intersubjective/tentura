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
    show MyWorkClosedResult, MyWorkCommittedRow, MyWorkInitResult;

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
      committedNonClosed:
          d.committedNonClosed.map(_mapInitCommittedRow).toList(),
      authoredClosedIds: d.authoredClosedIds.map((e) => e.id).toList(),
      committedClosedIds:
          d.committedClosedIds.map((e) => e.beacon.id).toList(),
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
      committedClosed:
          d.committedClosed.map(_mapClosedCommittedRow).toList(),
    );
  }

  static MyWorkCommittedRow _mapInitCommittedRow(
    GMyWorkInitData_committedNonClosed e,
  ) {
    final b = e.beacon;
    final beacon = BeaconModel(b).toEntity();
    final forwarders = b.forward_edges
        .map((fe) => UserModel(fe.sender).toEntity())
        .toList();
    return (
      beacon: beacon,
      commitMessage: e.message,
      helpType: e.help_type,
      authorResponseType: CoordinationResponseType.tryFromInt(
        e.coordination?.response_type,
      ),
      forwarderSenders: forwarders,
      commitmentRowUpdatedAt: e.updated_at,
      authorCoordinationUpdatedAt: e.coordination?.updated_at,
    );
  }

  static MyWorkCommittedRow _mapClosedCommittedRow(
    GMyWorkClosedData_committedClosed e,
  ) {
    final b = e.beacon;
    final beacon = BeaconModel(b).toEntity();
    final forwarders = b.forward_edges
        .map((fe) => UserModel(fe.sender).toEntity())
        .toList();
    return (
      beacon: beacon,
      commitMessage: e.message,
      helpType: e.help_type,
      authorResponseType: CoordinationResponseType.tryFromInt(
        e.coordination?.response_type,
      ),
      forwarderSenders: forwarders,
      commitmentRowUpdatedAt: e.updated_at,
      authorCoordinationUpdatedAt: e.coordination?.updated_at,
    );
  }

  static const _label = 'MyWork';
}
