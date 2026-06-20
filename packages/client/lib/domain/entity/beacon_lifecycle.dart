/// Beacon lifecycle (`beacon.state` smallint in DB / Hasura).
enum BeaconLifecycle {
  open(0),
  cancelled(1),
  deleted(2),
  draft(3),
  /// Post-success review window ("Wrapping up").
  reviewOpen(5),
  /// Review complete / done without review window.
  closed(6);

  const BeaconLifecycle(this.smallintValue);

  final int smallintValue;

  static BeaconLifecycle fromSmallint(int v) => switch (v) {
        0 => BeaconLifecycle.open,
        1 => BeaconLifecycle.cancelled,
        2 => BeaconLifecycle.deleted,
        3 => BeaconLifecycle.draft,
        4 => BeaconLifecycle.closed, // legacy PENDING_REVIEW → closed
        5 => BeaconLifecycle.reviewOpen,
        6 => BeaconLifecycle.closed,
        _ => BeaconLifecycle.open,
      };

  /// Union of non-finished lifecycles (OPEN, DRAFT, WRAPPING UP).
  bool get isActiveSection =>
      this == open || this == draft || this == reviewOpen;

  /// DELETED only — lifecycle tombstone; finished cards use [isFinished].
  bool get isClosedSection => this == deleted;

  bool get isReviewWindowOpen => this == reviewOpen;

  bool get isWrappingUp => this == reviewOpen;

  bool get isFinished => this == cancelled || this == closed;

  /// NOW line + coordination items editable in OPEN and WRAPPING UP.
  bool get allowsCoordination => this == open || this == reviewOpen;

  /// Forwarding only while OPEN.
  bool get allowsForward => this == open;

  /// My Work "Drafts" tab (`beacon.state` == 3).
  bool get isMyWorkDraftsTab => this == draft;

  /// My Work "Active" tab — OPEN only (published, not draft).
  bool get isMyWorkActiveTab => this == open;

  /// My Work "Review" tab — evaluation / post-close review window.
  bool get isMyWorkReviewTab => this == reviewOpen;
}
