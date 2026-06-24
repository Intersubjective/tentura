import 'beacon_status.dart';

/// Semantic reason for a persisted status transition (Activity / audit).
enum BeaconStatusTransitionReason {
  publish,
  needsMoreHelp,
  enoughHelp,
  neutralOpen,
  reviewWindowOpened,
  directClose,
  authorCloseNow,
  reviewExpired,
  reopenedFromReview,
  cancelled,
  deleted,
}

/// Pure verdict from [validateBeaconStatusTransition].
enum BeaconStatusTransitionVerdict {
  allowed,
  noop,
  invalidSource,
  invalidTarget,
  disallowed,
}

typedef BeaconStatusTransitionResult = ({
  BeaconStatusTransitionVerdict verdict,
  String? message,
});

/// Allowed persisted transitions (single source of truth).
const _allowedTransitions = <(BeaconStatus, BeaconStatus)>{
  // Create / publish
  (BeaconStatus.draft, BeaconStatus.open),
  // Open-family coordination intent
  (BeaconStatus.open, BeaconStatus.needsMoreHelp),
  (BeaconStatus.needsMoreHelp, BeaconStatus.open),
  (BeaconStatus.open, BeaconStatus.enoughHelp),
  (BeaconStatus.enoughHelp, BeaconStatus.open),
  (BeaconStatus.needsMoreHelp, BeaconStatus.enoughHelp),
  (BeaconStatus.enoughHelp, BeaconStatus.needsMoreHelp),
  // Cancel / close from open-family
  (BeaconStatus.open, BeaconStatus.cancelled),
  (BeaconStatus.needsMoreHelp, BeaconStatus.cancelled),
  (BeaconStatus.enoughHelp, BeaconStatus.cancelled),
  (BeaconStatus.open, BeaconStatus.closed),
  (BeaconStatus.needsMoreHelp, BeaconStatus.closed),
  (BeaconStatus.enoughHelp, BeaconStatus.closed),
  (BeaconStatus.open, BeaconStatus.reviewOpen),
  (BeaconStatus.needsMoreHelp, BeaconStatus.reviewOpen),
  (BeaconStatus.enoughHelp, BeaconStatus.reviewOpen),
  // Review window
  (BeaconStatus.reviewOpen, BeaconStatus.open),
  (BeaconStatus.reviewOpen, BeaconStatus.needsMoreHelp),
  (BeaconStatus.reviewOpen, BeaconStatus.enoughHelp),
  (BeaconStatus.reviewOpen, BeaconStatus.closed),
  // Delete
  (BeaconStatus.draft, BeaconStatus.deleted), // hard delete uses row removal
  (BeaconStatus.open, BeaconStatus.deleted),
  (BeaconStatus.needsMoreHelp, BeaconStatus.deleted),
  (BeaconStatus.enoughHelp, BeaconStatus.deleted),
  (BeaconStatus.cancelled, BeaconStatus.deleted),
  (BeaconStatus.closed, BeaconStatus.deleted),
  (BeaconStatus.reviewOpen, BeaconStatus.deleted),
};

bool isBeaconOpenFamilyStatus(BeaconStatus status) => status.isOpenFamily;

/// Returns whether [value] is a legal persisted smallint for `beacon.status`.
bool isAllowedBeaconStatusSmallint(int value) => switch (value) {
      0 || 1 || 2 || 3 || 5 || 6 || 7 || 8 => true,
      _ => false,
    };

BeaconStatusTransitionResult validateBeaconStatusTransition({
  required BeaconStatus from,
  required BeaconStatus to,
  BeaconStatusTransitionReason? reason,
}) {
  if (from == to) {
    return (verdict: BeaconStatusTransitionVerdict.noop, message: null);
  }
  if (!_allowedTransitions.contains((from, to))) {
    return (
      verdict: BeaconStatusTransitionVerdict.disallowed,
      message: 'Transition $from -> $to is not allowed',
    );
  }
  return (verdict: BeaconStatusTransitionVerdict.allowed, message: null);
}

/// Maps author coordination menu selection to target status.
BeaconStatus coordinationTargetStatus(int coordinationSmallint) =>
    switch (coordinationSmallint) {
      2 || 7 => BeaconStatus.needsMoreHelp,
      3 || 8 => BeaconStatus.enoughHelp,
      _ => BeaconStatus.open,
    };

String reasonStringForTransition(BeaconStatusTransitionReason reason) =>
    switch (reason) {
      BeaconStatusTransitionReason.publish => 'published',
      BeaconStatusTransitionReason.needsMoreHelp => 'needsMoreHelp',
      BeaconStatusTransitionReason.enoughHelp => 'enoughHelp',
      BeaconStatusTransitionReason.neutralOpen => 'neutralOpen',
      BeaconStatusTransitionReason.reviewWindowOpened => 'reviewWindowOpened',
      BeaconStatusTransitionReason.directClose => 'directClose',
      BeaconStatusTransitionReason.authorCloseNow => 'authorCloseNow',
      BeaconStatusTransitionReason.reviewExpired => 'reviewExpired',
      BeaconStatusTransitionReason.reopenedFromReview => 'reopenedFromReview',
      BeaconStatusTransitionReason.cancelled => 'cancelled',
      BeaconStatusTransitionReason.deleted => 'deleted',
    };
