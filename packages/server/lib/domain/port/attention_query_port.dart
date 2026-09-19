import 'package:tentura_server/domain/attention/attention_models.dart';

// Feed and summary are one atomic read operation by contract.
// ignore: one_member_abstracts
abstract interface class AttentionQueryPort {
  /// Returns unread summary and one authorized page from one database statement.
  Future<AttentionFeed> attentionFeed({
    required String accountId,
    required AttentionFeedView view,
    AttentionCursor? cursor,
    String? search,
    AttentionSurface? surface,
    int limit = 50,
  });

  /// Per-surface unread totals and the global needs-you count from one snapshot.
  Future<AttentionSurfaceSummary> surfaceSummary({required String accountId});

  /// Authorized unread attention for a bounded set of Beacon ids.
  ///
  /// This deliberately exposes no Inbox/My Work presentation concepts. The
  /// client presenter intersects the result with its current surface models.
  Future<Set<String>> unreadForBeacons({
    required String accountId,
    required Set<String> beaconIds,
  });

  /// Authorized beacon ids for which the viewer holds a live obligation.
  ///
  /// This deliberately exposes no Inbox/My Work presentation concepts. The
  /// client presenter intersects the result with its current surface models.
  Future<Set<String>> liveObligationBeacons({
    required String accountId,
  });

  /// Per-request My Work attention for Beacons in the caller's responsibility
  /// scope. Omits Beacons with no unseen receipts and no live obligations.
  Future<List<MyWorkBeaconAttention>> myWorkAttention({
    required String accountId,
    required Set<String> beaconIds,
  });

  /// Pinned «For you» offers ordered by [effectiveActivityAt] desc.
  ///
  /// Cursor is `(effectiveActivityAt, beaconId)` and is independent of any
  /// client-side display reordering.
  Future<ActivityOfferPage> activityOffers({
    required String accountId,
    AttentionCursor? cursor,
    int limit = 20,
  });

  /// The viewer's own authorized receipt history for one Request (D17).
  ///
  /// Unlike [activityAttention] this spans every surface and every lifecycle
  /// state — cleared and settled receipts included, which is the point: they
  /// are exactly the rows the live surfaces have stopped showing. Newest
  /// first, behind the same authorization wall and the same `(createdAt, id)`
  /// cursor as [attentionFeed].
  Future<AttentionPage> attentionRequestHistory({
    required String accountId,
    required String beaconId,
    AttentionCursor? cursor,
    int limit = 50,
  });

  /// Older Activity child events for one beacon (expand-more after the
  /// page-embedded preview). Cursor is `(createdAt, id)` on child receipts.
  Future<ActivityBeaconAttention> activityAttention({
    required String accountId,
    required String beaconId,
    AttentionCursor? cursor,
    int limit = 20,
  });
}
