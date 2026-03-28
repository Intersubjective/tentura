import 'package:injectable/injectable.dart';

import 'package:tentura/data/model/user_model.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/profile.dart';

import '../../domain/entity/forward_edge.dart';
import '../gql/_g/forward_beacon.req.gql.dart';
import '../gql/_g/forward_edges_fetch.req.gql.dart';
import '../gql/_g/beacon_commit.req.gql.dart';
import '../gql/_g/beacon_withdraw.req.gql.dart';
import '../gql/_g/commitments_fetch.req.gql.dart';
import '../gql/_g/beacon_updates_fetch.req.gql.dart';

@lazySingleton
class ForwardRepository {
  ForwardRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  Future<String> forwardBeacon({
    required String beaconId,
    required List<String> recipientIds,
    String? note,
    String? context,
    String? parentEdgeId,
  }) => _remoteApiService
      .request(
        GForwardBeaconReq(
          (r) => r..vars.beaconId = beaconId
            ..vars.recipientIds.addAll(recipientIds)
            ..vars.note = note
            ..vars.context = context
            ..vars.parentEdgeId = parentEdgeId,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label).beaconForward);

  Future<List<ForwardEdge>> fetchEdges({required String beaconId}) =>
      _remoteApiService
          .request(
            GForwardEdgesFetchReq((r) => r..vars.beaconId = beaconId),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then(
            (r) => r
                .dataOrThrow(label: _label)
                .beacon_forward_edge
                .map(
                  (e) => ForwardEdge(
                    id: e.id,
                    beaconId: e.beacon_id,
                    context: e.context ?? '',
                    note: e.note,
                    parentEdgeId: e.parent_edge_id,
                    batchId: e.batch_id,
                    createdAt: e.created_at,
                    sender: (e.sender as UserModel).toEntity(),
                    recipient: (e.recipient as UserModel).toEntity(),
                  ),
                )
                .toList(),
          );

  Future<List<({Profile user, String message, DateTime createdAt})>>
      fetchCommitments({required String beaconId}) => _remoteApiService
          .request(
            GCommitmentsFetchReq((r) => r..vars.beaconId = beaconId),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then(
            (r) => r
                .dataOrThrow(label: _label)
                .beacon_commitment
                .map(
                  (e) => (
                    user: (e.user as UserModel).toEntity(),
                    message: e.message,
                    createdAt: e.created_at,
                  ),
                )
                .toList(),
          );

  Future<List<({Profile author, String content, DateTime createdAt})>>
      fetchUpdates({required String beaconId}) => _remoteApiService
          .request(
            GBeaconUpdatesFetchReq((r) => r..vars.beaconId = beaconId),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then(
            (r) => r
                .dataOrThrow(label: _label)
                .beacon_update
                .map(
                  (e) => (
                    author: (e.author as UserModel).toEntity(),
                    content: e.content,
                    createdAt: e.created_at,
                  ),
                )
                .toList(),
          );

  Future<bool> commit({
    required String beaconId,
    String? message,
  }) => _remoteApiService
      .request(
        GBeaconCommitReq(
          (r) => r..vars.beaconId = beaconId..vars.message = message,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label).beaconCommit);

  Future<bool> withdraw({required String beaconId}) => _remoteApiService
      .request(GBeaconWithdrawReq((r) => r..vars.beaconId = beaconId))
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label).beaconWithdraw);

  static const _label = 'Forward';
}
