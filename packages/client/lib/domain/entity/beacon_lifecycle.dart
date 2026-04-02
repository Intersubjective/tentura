/// Beacon lifecycle (`beacon.state` smallint in DB / Hasura).
enum BeaconLifecycle {
  open(0),
  closed(1),
  deleted(2),
  draft(3),
  pendingReview(4),
  /// Post-success review window open (Phase 1 evaluation).
  closedReviewOpen(5),
  /// Review window completed; beacon remains closed for listing.
  closedReviewComplete(6);

  const BeaconLifecycle(this.smallintValue);

  final int smallintValue;

  static BeaconLifecycle fromSmallint(int v) => switch (v) {
        0 => BeaconLifecycle.open,
        1 => BeaconLifecycle.closed,
        2 => BeaconLifecycle.deleted,
        3 => BeaconLifecycle.draft,
        4 => BeaconLifecycle.pendingReview,
        5 => BeaconLifecycle.closedReviewOpen,
        6 => BeaconLifecycle.closedReviewComplete,
        _ => BeaconLifecycle.open,
      };

  /// Union of non-closed lifecycles (OPEN, DRAFT, PENDING_REVIEW, CLOSED_REVIEW_OPEN).
  /// Used for listing / `Beacon.isListed`, not the My Work "Active" tab alone.
  bool get isActiveSection =>
      this == open ||
      this == draft ||
      this == pendingReview ||
      this == closedReviewOpen;

  /// CLOSED, DELETED, CLOSED_REVIEW_COMPLETE — My Work "Closed" tab.
  bool get isClosedSection =>
      this == closed || this == deleted || this == closedReviewComplete;

  bool get isReviewWindowOpen => this == closedReviewOpen;

  /// My Work "Drafts" tab (`beacon.state` == 3).
  bool get isMyWorkDraftsTab => this == draft;

  /// My Work "Active" tab — OPEN only (published, not draft).
  bool get isMyWorkActiveTab => this == open;

  /// My Work "Review" tab — evaluation / post-close review window.
  bool get isMyWorkReviewTab =>
      this == pendingReview || this == closedReviewOpen;
}
