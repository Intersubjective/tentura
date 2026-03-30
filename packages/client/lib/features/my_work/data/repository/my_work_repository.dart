import 'dart:async';

import 'package:injectable/injectable.dart';

import 'package:tentura/data/model/beacon_model.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/beacon.dart';

import '../gql/_g/my_work_fetch.req.gql.dart';

@lazySingleton
class MyWorkRepository {
  MyWorkRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  static const _kNetworkTimeout = Duration(seconds: 60);

  Future<List<Beacon>> fetchAuthoredActive({
    required String userId,
    required String context,
  }) async {
    final r = await _remoteApiService
        .request(
          GMyWorkAuthoredActiveReq(
            (r) => r..vars.userId = userId..vars.context = context,
          ),
        )
        .timeout(_kNetworkTimeout)
        .first;
    final v = r.dataOrThrow(label: _label).beacon;
    return v.map((e) => (e as BeaconModel).toEntity()).toList();
  }

  Future<List<Beacon>> fetchAuthoredClosed({
    required String userId,
    required String context,
  }) async {
    final r = await _remoteApiService
        .request(
          GMyWorkAuthoredClosedReq(
            (r) => r..vars.userId = userId..vars.context = context,
          ),
        )
        .timeout(_kNetworkTimeout)
        .first;
    final v = r.dataOrThrow(label: _label).beacon;
    return v.map((e) => (e as BeaconModel).toEntity()).toList();
  }

  Future<List<Beacon>> fetchCommittedActive({
    required String userId,
    required String context,
  }) async {
    final r = await _remoteApiService
        .request(
          GMyWorkCommittedActiveReq(
            (r) => r..vars.userId = userId..vars.context = context,
          ),
        )
        .timeout(_kNetworkTimeout)
        .first;
    final v = r.dataOrThrow(label: _label).beacon_commitment;
    return v.map((e) => (e.beacon as BeaconModel).toEntity()).toList();
  }

  Future<List<Beacon>> fetchCommittedClosed({
    required String userId,
    required String context,
  }) async {
    final r = await _remoteApiService
        .request(
          GMyWorkCommittedClosedReq(
            (r) => r..vars.userId = userId..vars.context = context,
          ),
        )
        .timeout(_kNetworkTimeout)
        .first;
    final v = r.dataOrThrow(label: _label).beacon_commitment;
    return v.map((e) => (e.beacon as BeaconModel).toEntity()).toList();
  }

  static const _label = 'MyWork';
}
