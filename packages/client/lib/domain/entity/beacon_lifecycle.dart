/// Beacon lifecycle (`beacon.state` smallint in DB / Hasura).
enum BeaconLifecycle {
  open(0),
  closed(1),
  deleted(2),
  draft(3),
  pendingReview(4);

  const BeaconLifecycle(this.smallintValue);

  final int smallintValue;

  static BeaconLifecycle fromSmallint(int v) => switch (v) {
        0 => BeaconLifecycle.open,
        1 => BeaconLifecycle.closed,
        2 => BeaconLifecycle.deleted,
        3 => BeaconLifecycle.draft,
        4 => BeaconLifecycle.pendingReview,
        _ => BeaconLifecycle.open,
      };

  /// OPEN, DRAFT, PENDING_REVIEW — shown in My Work "Active".
  bool get isActiveSection => this == open || this == draft || this == pendingReview;

  /// CLOSED, DELETED — shown in My Work "Closed".
  bool get isClosedSection => this == closed || this == deleted;
}
