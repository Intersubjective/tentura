import 'package:tentura_server/domain/entity/user_block_entity.dart';

abstract class UserBlockRepositoryPort {
  Future<void> block({
    required String blockerId,
    required String blockedId,
    required int cascadeMode,
  });

  Future<void> unblock({required String blockerId, required String blockedId});

  /// Count intent rows updated by [blockerId] within the trailing [window]
  /// (spam-control rate limiting; `updated_at` advances on every block action).
  Future<int> countRecentByBlocker({
    required String blockerId,
    required Duration window,
  });

  /// Promote an inherited row to a direct block (§6.3 escape hatch).
  Future<void> promoteToDirect({
    required String blockerId,
    required String blockedId,
  });

  Future<List<UserBlockIntentEntity>> listIntents(String blockerId);

  Future<List<UserBlockEntity>> listInherited({
    required String blockerId,
    required String originId,
  });

  Future<BlockPreviewEntity> preview({
    required String blockerId,
    required String blockedId,
    required int cascadeMode,
  });

  Future<bool> isBlockedPair({required String a, required String b});

  /// Batch form for list surfaces — one round trip.
  Future<Set<String>> hiddenPeerIds({
    required String viewerId,
    required Iterable<String> peerIds,
  });

  /// Called by the use case on every block after the row is written (§6.4).
  Future<void> applyWithdrawal({
    required String blockerId,
    required String blockedId,
  });

  // --- cascade job surface ---
  Future<List<UserBlockIntentEntity>> claimPendingCascades({required int limit});

  Future<int> materializeCascadeBatch({
    required String blockerId,
    required String blockedId,
    required int limit,
  });

  Future<int> runReleaseSweep({required int limit});
}
