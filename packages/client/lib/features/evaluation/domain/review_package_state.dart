/// The state of one reviewer's package in one review window.
///
/// This is the primary variable of every review surface (#162). Checklist
/// completeness is only progress and never decides which action is offered.
enum ReviewPackageState {
  /// No window, or the viewer is not a reviewer in it.
  notEnrolled,

  /// Enrolled, but the window has no targets for this viewer.
  empty,

  /// Not sent, some required target still unanswered.
  inProgress,

  /// Not sent, every required target answered.
  readyToSend,

  /// Sent and unchanged since.
  sent,

  /// Sent once, then edited: the server demoted the package and it must be sent
  /// again or it is discarded when the request closes.
  changedNotSent,

  /// The window disappeared while the viewer was enrolled (the author reopened
  /// the request).
  paused,

  /// The window closed and the viewer had sent.
  closed,

  /// The window closed and the viewer had not sent; the rows were deleted.
  closedUnsent,
}

/// Derives the package state.
///
/// [userReviewStatus] is the server's per-user code: -1 not enrolled,
/// 0 not started, 1 in progress, 2 sent, 3 legacy skipped, 4 expired unsent.
/// It cannot distinguish "never sent" from "sent then edited" on its own —
/// [sentAt] does that (see issue #162).
ReviewPackageState deriveReviewPackageState({
  required bool beaconIsInReview,
  required bool beaconIsClosed,
  required bool hasWindow,
  required bool windowComplete,
  required int? userReviewStatus,
  required DateTime? sentAt,
  required int requiredTotal,
  required int requiredAnswered,
  required int totalTargets,
}) {
  if (windowComplete || beaconIsClosed) {
    return sentAt != null
        ? ReviewPackageState.closed
        : ReviewPackageState.closedUnsent;
  }
  if (userReviewStatus == 4) {
    return ReviewPackageState.closedUnsent;
  }
  if (!hasWindow) {
    // A request that never had a window is not "paused" for a first-time
    // visitor; only a viewer who is in review can have lost one.
    return beaconIsInReview
        ? ReviewPackageState.notEnrolled
        : ReviewPackageState.paused;
  }
  if (userReviewStatus == null || userReviewStatus < 0) {
    return ReviewPackageState.notEnrolled;
  }
  if (userReviewStatus == 2) {
    return ReviewPackageState.sent;
  }
  if (totalTargets == 0) {
    return ReviewPackageState.empty;
  }
  final allRequiredAnswered = requiredAnswered >= requiredTotal;
  if (sentAt != null) {
    return allRequiredAnswered
        ? ReviewPackageState.changedNotSent
        : ReviewPackageState.inProgress;
  }
  return allRequiredAnswered
      ? ReviewPackageState.readyToSend
      : ReviewPackageState.inProgress;
}
