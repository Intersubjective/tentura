import 'dart:convert';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/beacon_activity_event_consts.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';

import '../bloc/beacon_view_state.dart';

/// Author-centric closure plausibility for HUD / confirmations (presentation-only).
enum BeaconClosureReadiness {
  /// Hard gate failed (non-author, not open, loading, etc.).
  notCloseable,

  /// Technically closeable but insufficient completion evidence.
  premature,

  /// Author should review coordination before treating closure as main action.
  waitingForReview,

  /// Strong signals suggest successful closure is the expected next step.
  readyToClose,

  /// Unresolved blocker / coordination state should be addressed first.
  blocked,
}

/// Where the Close affordance appears for the author.
enum ClosureActionPriority {
  hidden,
  overflow,
  secondary,
  primary,
}

/// A completion check the close sheet lists as not met yet (#474).
enum BeaconClosureCriterion {
  /// The author has not marked «Enough help».
  enoughHelp,

  /// No help offer has a useful or done result.
  usefulOrDoneResult,

  /// Some ordinary help offers are not settled (backup offers never count).
  offersSettled,
}

/// Summary for close confirmation sheet (counts / flags only).
class BeaconClosureConfirmationSummary {
  const BeaconClosureConfirmationSummary({
    required this.readiness,
    required this.hasOpenBlocker,
    required this.unansweredHelpOffersCount,
    required this.relevantHelpOffersCount,
    required this.unsettledRelevantCount,
    required this.hasWholeBeaconDoneSignal,
    required this.enoughHelpOffered,
    required this.hasSuccessfulHelpOfferResult,
    required this.requiresReviewWindow,
    this.missingCriteria = const {},
  });

  final BeaconClosureReadiness readiness;
  final bool hasOpenBlocker;
  final int unansweredHelpOffersCount;
  final int relevantHelpOffersCount;
  final int unsettledRelevantCount;
  final bool hasWholeBeaconDoneSignal;
  final bool enoughHelpOffered;
  final bool hasSuccessfulHelpOfferResult;
  final bool requiresReviewWindow;

  /// Checks not met yet, from the same inputs as [readiness]; the sheet only
  /// maps them to rows (#474).
  final Set<BeaconClosureCriterion> missingCriteria;

  /// Every completion check passes: the sheet offers a plain close (or the
  /// start of the final check) with no warning.
  bool get allChecksPass =>
      readiness == BeaconClosureReadiness.readyToClose ||
      (readiness == BeaconClosureReadiness.waitingForReview &&
          missingCriteria.isEmpty);
}

bool closeHardGate(BeaconViewState state) {
  // TODO(steward-delegated-closer): OR delegated closure permission into this gate.
  if (!state.isBeaconMine) return false;
  if (!state.beacon.status.isOpenFamily) return false;
  if (!state.isSuccess) return false;
  if (state.beacon.author.id.isEmpty) return false;
  if (state.isLoading) return false;
  return true;
}

BeaconParticipant? beaconParticipantForUser(
  BeaconViewState state,
  String userId,
) {
  if (userId.isEmpty) return null;
  for (final p in state.roomParticipants) {
    if (p.userId == userId) return p;
  }
  return null;
}

bool _hasOpenBlocker(BeaconViewState state) {
  final coord = state.openCoordinationBlocker;
  if (coord != null && coord.isOpen) return true;
  final t = state.beaconRoomCue?.openBlockerTitle?.trim();
  return t != null && t.isNotEmpty;
}

bool _authorParticipantNeedsInfo(BeaconViewState state) {
  final authorId = state.beacon.author.id;
  if (authorId.isEmpty) return false;
  final p = beaconParticipantForUser(state, authorId);
  return p != null && p.status == BeaconParticipantStatusBits.needsInfo;
}

bool _isRelevantHelpOffer(TimelineHelpOffer c) =>
    !c.isWithdrawn &&
    c.coordinationResponse != CoordinationResponseType.notSuitable &&
    c.coordinationResponse != CoordinationResponseType.overlapping;

Iterable<TimelineHelpOffer> relevantHelpOffers(BeaconViewState state) =>
    state.helpOffers.where(_isRelevantHelpOffer);

/// Parsed `beacon_activity_event.diff_json` for whole-beacon done (not message-level).
///
/// Server currently emits `doneMarked` with `{kind: message}` only; whole-beacon scope
/// requires structured keys such as `scope: wholeBeacon` or `target: wholeBeacon`.
bool activityEventIndicatesWholeBeaconDone(String? diffJson) {
  if (diffJson == null || diffJson.trim().isEmpty) return false;
  try {
    final decoded = jsonDecode(diffJson);
    if (decoded is! Map) return false;
    final scope = decoded['scope'];
    final target = decoded['target'];
    return scope == 'wholeBeacon' || target == 'wholeBeacon';
  } on Object {
    return false;
  }
}

bool hasExplicitWholeBeaconDoneSignal(BeaconViewState state) {
  for (final e in state.roomActivityEvents) {
    if (e.type != BeaconActivityEventTypeBits.doneMarked) continue;
    if (activityEventIndicatesWholeBeaconDone(e.diffJson)) return true;
  }
  return false;
}

bool hasSuccessfulHelpOfferResult(BeaconViewState state) {
  for (final c in relevantHelpOffers(state)) {
    if (c.coordinationResponse == CoordinationResponseType.useful) return true;
    final p = beaconParticipantForUser(state, c.user.id);
    if (p == null) continue;
    if (p.status == BeaconParticipantStatusBits.done) return true;
    if (p.nextMoveStatus == BeaconNextMoveStatusBits.done) return true;
  }
  return false;
}

bool authorMarkedEnoughHelp(BeaconViewState state) =>
    state.beacon.status == BeaconStatus.enoughHelp;

bool helpOfferRowSettled(TimelineHelpOffer c, BeaconViewState state) {
  if (c.roleLabel?.trim().isNotEmpty ?? false) return true;
  final p = beaconParticipantForUser(state, c.user.id);
  if (p != null) {
    if (p.status == BeaconParticipantStatusBits.withdrawn ||
        p.status == BeaconParticipantStatusBits.done) {
      return true;
    }
    final nms = p.nextMoveStatus;
    if (nms == BeaconNextMoveStatusBits.done ||
        nms == BeaconNextMoveStatusBits.obsolete) {
      return true;
    }
  }
  if (c.coordinationResponse == CoordinationResponseType.useful) return true;
  return false;
}

/// Relevant offers that still need settling. A backup offer stays a backup
/// on purpose («Decline remaining offers» keeps it), so it never counts as
/// unsettled (#474).
Iterable<TimelineHelpOffer> unsettledRelevantHelpOffers(
  BeaconViewState state,
) => relevantHelpOffers(
  state,
).where((c) => !c.isBackup && !helpOfferRowSettled(c, state));

bool allRelevantHelpOffersSettled(BeaconViewState state) {
  if (relevantHelpOffers(state).isEmpty) return false;
  return unsettledRelevantHelpOffers(state).isEmpty;
}

bool hasClosureBlockingState(BeaconViewState state) =>
    state.beacon.status == BeaconStatus.needsMoreHelp ||
    _hasClosureBlockerOtherThanStatus(state);

/// «Needs more help» blocks closing and nothing else does: marking «Enough
/// help» is then the one step that unblocks Wrapping up / Closed (B081).
bool closureBlockedOnlyByNeedsMoreHelp(BeaconViewState state) =>
    state.beacon.status == BeaconStatus.needsMoreHelp &&
    !_hasClosureBlockerOtherThanStatus(state);

bool _hasClosureBlockerOtherThanStatus(BeaconViewState state) {
  if (_hasOpenBlocker(state)) return true;

  if (_authorParticipantNeedsInfo(state)) return true;

  final authorId = state.beacon.author.id;
  for (final c in relevantHelpOffers(state)) {
    final p = beaconParticipantForUser(state, c.user.id);
    if (p == null) continue;
    if (p.status == BeaconParticipantStatusBits.blocked) return true;
    if (p.status == BeaconParticipantStatusBits.needsInfo &&
        c.user.id == authorId) {
      return true;
    }
  }

  return false;
}

BeaconClosureReadiness computeClosureReadiness(BeaconViewState state) {
  if (!closeHardGate(state)) {
    return BeaconClosureReadiness.notCloseable;
  }

  if (hasClosureBlockingState(state)) {
    return BeaconClosureReadiness.blocked;
  }

  final explicitDone = hasExplicitWholeBeaconDoneSignal(state);
  final successfulResult = hasSuccessfulHelpOfferResult(state);
  final enoughHelp = authorMarkedEnoughHelp(state);
  final settled = allRelevantHelpOffersSettled(state);

  if (explicitDone) {
    return BeaconClosureReadiness.readyToClose;
  }

  if (enoughHelp && successfulResult && settled) {
    return BeaconClosureReadiness.readyToClose;
  }

  if (enoughHelp || successfulResult || settled) {
    return BeaconClosureReadiness.waitingForReview;
  }

  return BeaconClosureReadiness.premature;
}

ClosureActionPriority closureActionPriorityFor(
  BeaconClosureReadiness readiness, {
  required bool allowForceCloseWhenBlocked,
}) {
  switch (readiness) {
    case BeaconClosureReadiness.notCloseable:
      return ClosureActionPriority.hidden;
    case BeaconClosureReadiness.blocked:
      return allowForceCloseWhenBlocked
          ? ClosureActionPriority.overflow
          : ClosureActionPriority.hidden;
    case BeaconClosureReadiness.premature:
      return ClosureActionPriority.overflow;
    case BeaconClosureReadiness.waitingForReview:
      return ClosureActionPriority.secondary;
    case BeaconClosureReadiness.readyToClose:
      return ClosureActionPriority.primary;
  }
}

bool helpOfferIsCommitter(TimelineHelpOffer offer) =>
    offer.stakeState == CommitmentStakeState.acknowledged;

bool beaconStateHasCommitters(BeaconViewState state) {
  final displayStatus = state.displayStatus;
  if (displayStatus != null) {
    return displayStatus.everAcknowledgedCommitterCount > 0;
  }
  return state.helpOffers.any(helpOfferIsCommitter);
}

/// `null` when server display status is not loaded yet (close must stay disabled).
bool? expectedRequiresReviewWindowForState(BeaconViewState state) {
  final displayStatus = state.displayStatus;
  if (displayStatus == null) return null;
  return displayStatus.everAcknowledgedCommitterCount > 0;
}

bool closeReviewWindowExpectationKnown(BeaconViewState state) =>
    state.displayStatus != null;

BeaconClosureConfirmationSummary buildClosureConfirmationSummary(
  BeaconViewState state,
) {
  final readiness = computeClosureReadiness(state);
  final relevant = relevantHelpOffers(state).toList();
  final unsettled = unsettledRelevantHelpOffers(state).length;
  final enoughHelp = authorMarkedEnoughHelp(state);
  final successfulResult = hasSuccessfulHelpOfferResult(state);
  final judged =
      readiness == BeaconClosureReadiness.waitingForReview ||
      readiness == BeaconClosureReadiness.premature;

  return BeaconClosureConfirmationSummary(
    readiness: readiness,
    hasOpenBlocker: _hasOpenBlocker(state),
    unansweredHelpOffersCount: state.unansweredHelpOffersCount,
    relevantHelpOffersCount: relevant.length,
    unsettledRelevantCount: unsettled,
    hasWholeBeaconDoneSignal: hasExplicitWholeBeaconDoneSignal(state),
    enoughHelpOffered: enoughHelp,
    hasSuccessfulHelpOfferResult: successfulResult,
    requiresReviewWindow: expectedRequiresReviewWindowForState(state) ?? false,
    missingCriteria: {
      if (judged && !enoughHelp) BeaconClosureCriterion.enoughHelp,
      if (judged && !successfulResult)
        BeaconClosureCriterion.usefulOrDoneResult,
      if (unsettled > 0 && readiness != BeaconClosureReadiness.readyToClose)
        BeaconClosureCriterion.offersSettled,
    },
  );
}

extension BeaconViewClosureX on BeaconViewState {
  BeaconClosureReadiness get closureReadiness => computeClosureReadiness(this);

  ClosureActionPriority get closureActionPriority => closureActionPriorityFor(
    closureReadiness,
    allowForceCloseWhenBlocked: kBeaconAllowForceCloseWhenBlocked,
  );
}
