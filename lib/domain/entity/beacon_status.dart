/// Canonical persisted beacon status (`beacon.status` smallint).
enum BeaconStatus {
  open(0),
  cancelled(1),
  deleted(2),
  draft(3),
  reviewOpen(5),
  closed(6),
  needsMoreHelp(7),
  enoughHelp(8);

  const BeaconStatus(this.smallintValue);

  final int smallintValue;

  static const openFamilyValues = {0, 7, 8};

  static BeaconStatus fromSmallint(int v) => switch (v) {
        0 => BeaconStatus.open,
        1 => BeaconStatus.cancelled,
        2 => BeaconStatus.deleted,
        3 => BeaconStatus.draft,
        4 => BeaconStatus.closed, // legacy PENDING_REVIEW → closed
        5 => BeaconStatus.reviewOpen,
        6 => BeaconStatus.closed,
        7 => BeaconStatus.needsMoreHelp,
        8 => BeaconStatus.enoughHelp,
        _ => BeaconStatus.open,
      };

  bool get isOpenFamily => openFamilyValues.contains(smallintValue);

  /// Terminal for coordination / status menu (not draft hard-delete).
  bool get isTerminal =>
      this == cancelled ||
      this == closed ||
      this == deleted;

  bool get isFinished => this == cancelled || this == closed;

  bool get allowsCoordination => isOpenFamily || this == reviewOpen;

  bool get allowsForward => isOpenFamily;

  bool get isReviewWindowOpen => this == reviewOpen;

  bool get isWrappingUp => this == reviewOpen;

  /// Union of non-finished lifecycles (open-family, DRAFT, WRAPPING UP).
  bool get isActiveSection =>
      isOpenFamily || this == draft || this == reviewOpen;

  /// DELETED only — lifecycle tombstone; finished cards use [isFinished].
  bool get isClosedSection => this == deleted;

  /// My Work "Drafts" tab.
  bool get isMyWorkDraftsTab => this == draft;

  /// My Work "Active" tab — published open-family only.
  bool get isMyWorkActiveTab => isOpenFamily;

  /// My Work "Review" tab — evaluation / post-close review window.
  bool get isMyWorkReviewTab => this == reviewOpen;
}
