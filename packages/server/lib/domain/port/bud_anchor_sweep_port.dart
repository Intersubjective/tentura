import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

/// A created bud whose child anchors have not been inherited yet (plan C8).
///
/// [childBeaconId] or [postId] is null when the child, or its Post parent, is
/// gone: there is nothing to inherit and the row is only marked.
class PendingBudAnchor {
  const PendingBudAnchor({
    required this.actorUserId,
    required this.clientCommandId,
    required this.childBeaconId,
    required this.postId,
  });

  final String actorUserId;
  final String clientCommandId;
  final String? childBeaconId;
  final String? postId;
}

/// A viewer's live anchor on a Post, and whether that Post is closed.
class BudPostPlacement {
  const BudPostPlacement({required this.position, required this.postClosed});

  final ConstellationAnchorPosition position;
  final bool postClosed;
}

/// Reads and marks for the anchor inheritance sweep (Arch §8.1). Every call
/// runs on its own, outside any held transaction: the sweep never keeps a row
/// lock while a per-viewer anchor apply runs.
abstract interface class BudAnchorSweepPort {
  /// Up to [limit] `beacon_child_commands` rows with a `bud_result`,
  /// `result_state = 0` and no `anchor_inherited_at`, oldest first. No lock.
  Future<List<PendingBudAnchor>> pendingBuds({required int limit});

  /// Viewers, in `viewer_id` order, who hold a live anchor on [postId], can
  /// read [childBeaconId], and have no anchor on the child yet.
  Future<List<String>> inheritingViewerIds({
    required String childBeaconId,
    required String postId,
  });

  /// The viewer's live anchor on [postId]; null when there is none.
  Future<BudPostPlacement?> postPlacement({
    required String viewerId,
    required String postId,
  });

  /// Sets `anchor_inherited_at` once (`WHERE anchor_inherited_at IS NULL`)
  /// in its own short transaction.
  Future<void> markInherited({
    required String actorUserId,
    required String clientCommandId,
  });
}
