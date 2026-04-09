import 'dart:async';

import 'package:injectable/injectable.dart';

import 'package:tentura/data/model/beacon_model.dart';
import 'package:tentura/data/model/user_model.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/profile.dart';

import '../gql/_g/my_work_fetch.data.gql.dart';
import '../gql/_g/my_work_fetch.req.gql.dart';

/// A committed row returned from the My Work fetch queries.
typedef MyWorkCommittedRow = ({
  Beacon beacon,
  String commitMessage,
  String? helpType,
  CoordinationResponseType? authorResponseType,
  List<Profile> forwarderSenders,
});

/// Result of [MyWorkRepository.fetchInit] (non-closed full rows + closed id hints).
typedef MyWorkInitResult = ({
  List<Beacon> authoredNonClosed,
  List<MyWorkCommittedRow> committedNonClosed,
  List<String> authoredClosedIds,
  List<String> committedClosedIds,
});

/// Result of [MyWorkRepository.fetchClosed] (full closed rows).
typedef MyWorkClosedResult = ({
  List<Beacon> authoredClosed,
  List<MyWorkCommittedRow> committedClosed,
});

@lazySingleton
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
    );
  }

  static const _label = 'MyWork';
}
