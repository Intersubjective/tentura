import 'package:tentura_server/domain/entity/user_block_entity.dart';

/// Cursor tuple for resumable release sweeps (§6.7): last-examined candidate
/// `(blocker_id, blocked_id, origin_id)`; `null` / empty ids mean table start.
typedef BlockReleaseSweepCursor = ({
  String blockerId,
  String blockedId,
  String originId,
});

/// One bounded release-sweep batch. [lastExaminedCandidate] is the last row from
/// the candidates CTE (examined, not necessarily deleted). [reachedTail] is true
/// when fewer than `limit` candidates were returned.
typedef BlockReleaseSweepBatch = ({
  int deletedCount,
  BlockReleaseSweepCursor? lastExaminedCandidate,
  bool reachedTail,
});

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

  /// Backfill inherited rows for signups that landed after [cascade_snapshot_at]
  /// but before their inviter was materialized (§6.7 step 5).
  Future<int> catchUpCascadeIntent({
    required String blockerId,
    required String blockedId,
  });

  Future<BlockReleaseSweepBatch> runReleaseSweep({
    required int limit,
    BlockReleaseSweepCursor? afterCursor,
  });
}
