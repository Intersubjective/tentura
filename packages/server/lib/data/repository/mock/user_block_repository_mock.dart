import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/user_block_entity.dart';
import 'package:tentura_server/domain/port/user_block_repository_port.dart';

@Injectable(
  as: UserBlockRepositoryPort,
  env: [Environment.test],
  order: 1,
)
class UserBlockRepositoryMock implements UserBlockRepositoryPort {
  @override
  Future<void> block({
    required String blockerId,
    required String blockedId,
    required int cascadeMode,
  }) => Future.value();

  @override
  Future<void> unblock({required String blockerId, required String blockedId}) =>
      Future.value();

  @override
  Future<int> countRecentByBlocker({
    required String blockerId,
    required Duration window,
  }) => Future.value(0);

  @override
  Future<void> promoteToDirect({
    required String blockerId,
    required String blockedId,
  }) => Future.value();

  @override
  Future<List<UserBlockIntentEntity>> listIntents(String blockerId) =>
      Future.value(const []);

  @override
  Future<List<UserBlockEntity>> listInherited({
    required String blockerId,
    required String originId,
  }) => Future.value(const []);

  @override
  Future<BlockPreviewEntity> preview({
    required String blockerId,
    required String blockedId,
    required int cascadeMode,
  }) => Future.value(const BlockPreviewEntity());

  @override
  Future<bool> isBlockedPair({required String a, required String b}) =>
      Future.value(false);

  @override
  Future<Set<String>> hiddenPeerIds({
    required String viewerId,
    required Iterable<String> peerIds,
  }) => Future.value(const {});

  @override
  Future<void> applyWithdrawal({
    required String blockerId,
    required String blockedId,
  }) => Future.value();

  @override
  Future<List<UserBlockIntentEntity>> claimPendingCascades({
    required int limit,
  }) => Future.value(const []);

  @override
  Future<int> materializeCascadeBatch({
    required String blockerId,
    required String blockedId,
    required int limit,
  }) => Future.value(0);

  @override
  Future<int> catchUpCascadeIntent({
    required String blockerId,
    required String blockedId,
  }) => Future.value(0);

  @override
  Future<BlockReleaseSweepBatch> runReleaseSweep({
    required int limit,
    BlockReleaseSweepCursor? afterCursor,
  }) => Future.value(
    (deletedCount: 0, lastExaminedCandidate: null, reachedTail: true),
  );
}
