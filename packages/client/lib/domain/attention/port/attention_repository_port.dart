import '../entity/activity_beacon_attention.dart';
import '../entity/activity_offer_sort_row.dart';
import '../entity/attention_clear.dart';
import '../entity/attention_feed.dart';
import '../entity/attention_summary.dart';
import '../entity/my_work_beacon_attention.dart';

abstract interface class AttentionRepositoryPort {
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  });

  /// Returns the unread subset of a bounded set of authorized Beacon ids.
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds);

  /// Authorized beacon ids where the viewer holds an unsettled requires-action receipt.
  Future<Set<String>> liveObligationBeacons();

  Future<int> markSeen(List<String> ids);

  Future<int> markUnseen(List<String> ids);

  Future<int> markAllSeen({AttentionSurface? surface});

  Future<AttentionSurfaceSummary> surfaceSummary();

  Future<int> markSeenForBeacon(String beaconId);

  Future<List<MyWorkBeaconAttention>> myWorkAttention(Set<String> beaconIds);

  Future<ActivityOfferPage> activityOffers({
    String? cursor,
    int limit = 20,
  });

  Future<ActivityBeaconAttention> activityAttention({
    required String beaconId,
    String? cursor,
    int limit = 20,
  });

  Future<int> settle({required String receiptId, required String kind});

  /// Captures the finite membership a clear may cover (D12 step 1).
  ///
  /// The server binds the membership to the returned token, so a clear can
  /// never grow past what was captured — not on retry, not on resume.
  Future<AttentionClearSnapshot> clearSnapshot({
    required AttentionClearCaptureKind kind,
    String? beaconId,
    String? receiptId,
  });

  /// Applies a capture. Idempotent under [operationId] (D12 step 7).
  Future<AttentionClearResult> clear({
    required String snapshotToken,
    required String operationId,
  });

  /// Bounded sweep. Resume a `partial` answer with the **same**
  /// [operationId]; a second id would capture a second membership.
  Future<AttentionDismissAllResult> dismissAll({
    required String operationId,
    int? maxBatches,
  });

  /// Bounded restore of exactly what [operationId] applied (D13).
  Future<AttentionUndoResult> undo({
    required String operationId,
    required String undoToken,
  });

  /// Repairs obligations and returns the authoritative summary (D15).
  Future<AttentionReconcileResult> reconcile();

  /// Cleared and active attention for one Request, newest first.
  Future<AttentionFeedPage> requestHistory({
    required String beaconId,
    String? cursor,
    int limit = 20,
  });
}
