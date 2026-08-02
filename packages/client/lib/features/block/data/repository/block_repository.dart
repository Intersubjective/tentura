import 'dart:async';

import 'package:injectable/injectable.dart';

import 'package:tentura/data/model/user_public_model.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';

import '../../domain/entity/user_block.dart';
import '../gql/_g/block_inherited_fetch.req.gql.dart';
import '../gql/_g/block_preview_fetch.req.gql.dart';
import '../gql/_g/block_promote.req.gql.dart';
import '../gql/_g/block_user.req.gql.dart';
import '../gql/_g/my_blocks_fetch.data.gql.dart';
import '../gql/_g/my_blocks_fetch.req.gql.dart';
import '../gql/_g/unblock_user.req.gql.dart';

@lazySingleton
class BlockRepository {
  BlockRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  final _controller = StreamController<RepositoryEvent<BlockIntent>>.broadcast();

  Stream<RepositoryEvent<BlockIntent>> get changes => _controller.stream;

  @disposeMethod
  Future<void> dispose() => _controller.close();

  Future<void> block({
    required String objectId,
    required int cascadeMode,
  }) async {
    await _remoteApiService
        .request(
          GUserBlockReq(
            (r) => r
              ..vars.objectId = objectId
              ..vars.cascadeMode = cascadeMode,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label));
    _controller.add(
      RepositoryEventCreate(BlockIntent(blocked: Profile(id: objectId))),
    );
  }

  Future<void> unblock({required String objectId}) async {
    await _remoteApiService
        .request(
          GUserUnblockReq((r) => r..vars.objectId = objectId),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label));
    _controller.add(
      RepositoryEventDelete(BlockIntent(blocked: Profile(id: objectId))),
    );
  }

  Future<void> promote({required String objectId}) => _remoteApiService
      .request(
        GUserBlockPromoteReq((r) => r..vars.objectId = objectId),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label));

  Future<List<BlockIntent>> fetchMyBlocks() => _remoteApiService
      .request(GMyBlocksReq())
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) => r
            .dataOrThrow(label: _label)
            .myBlocks
            .map<BlockIntent>(_blockIntentFromGql)
            .toList(),
      );

  Future<List<Profile>> fetchInherited({required String originId}) =>
      _remoteApiService
          .request(
            GBlockInheritedReq((r) => r..vars.originId = originId),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then(
            (r) => r
                .dataOrThrow(label: _label)
                .blockInherited
                .map((row) => (row as UserPublicModel).toEntity())
                .toList(),
          );

  Future<BlockPreview> preview({
    required String objectId,
    required int cascadeMode,
  }) => _remoteApiService
      .request(
        GBlockPreviewReq(
          (r) => r
            ..vars.objectId = objectId
            ..vars.cascadeMode = cascadeMode,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) {
        final row = r.dataOrThrow(label: _label).blockPreview;
        return BlockPreview(
          cascadeCandidateCount: row.cascadeCandidateCount,
          cascadeCapped: row.cascadeCapped,
          openCommitmentCount: row.openCommitmentCount,
          willWithdrawEdge: row.willWithdrawEdge,
        );
      });

  BlockIntent _blockIntentFromGql(GMyBlocksData_myBlocks row) => BlockIntent(
    blocked: (row.blocked as UserPublicModel).toEntity(),
    cascadeMode: row.cascadeMode,
    inheritedCount: row.inheritedCount,
    cascadeCapped: row.cascadeCapped,
    cascadePending: row.cascadePending,
  );

  static const _label = 'Block';
}
