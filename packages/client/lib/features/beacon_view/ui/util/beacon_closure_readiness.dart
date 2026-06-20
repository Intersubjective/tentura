import 'dart:convert';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/beacon_activity_event_consts.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/coordination_status.dart';

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
}

bool closeHardGate(BeaconViewState state) {
  // TODO(steward-delegated-closer): OR delegated closure permission into this gate.
  if (!state.isBeaconMine) return false;
  if (state.beacon.lifecycle != BeaconLifecycle.open) return false;
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
    state.beacon.coordinationStatus ==
    BeaconCoordinationStatus.enoughHelpOffered;

bool helpOfferRowSettled(TimelineHelpOffer c, BeaconViewState state) {
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

bool allRelevantHelpOffersSettled(BeaconViewState state) {
  final relevant = relevantHelpOffers(state).toList();
  if (relevant.isEmpty) return false;
  return relevant.every((c) => helpOfferRowSettled(c, state));
}

bool hasClosureBlockingState(BeaconViewState state) {
  if (_hasOpenBlocker(state)) return true;

  if (_authorParticipantNeedsInfo(state)) return true;

  if (state.beacon.coordinationStatus ==
      BeaconCoordinationStatus.moreOrDifferentHelpNeeded) {
    return true;
  }

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

  if (enoughHelp ||
      successfulResult ||
      settled) {
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
    !offer.isWithdrawn &&
    (offer.coordinationResponse == CoordinationResponseType.useful ||
        offer.coordinationResponse == CoordinationResponseType.needCoordination);

bool beaconStateHasCommitters(BeaconViewState state) =>
    state.helpOffers.any(helpOfferIsCommitter);

bool expectedRequiresReviewWindowForState(BeaconViewState state) =>
    beaconStateHasCommitters(state);

BeaconClosureConfirmationSummary buildClosureConfirmationSummary(
  BeaconViewState state,
) {
  final readiness = computeClosureReadiness(state);
  final relevant = relevantHelpOffers(state).toList();
  var unsettled = 0;
  for (final c in relevant) {
    if (!helpOfferRowSettled(c, state)) unsettled++;
  }

  return BeaconClosureConfirmationSummary(
    readiness: readiness,
    hasOpenBlocker: _hasOpenBlocker(state),
    unansweredHelpOffersCount: state.unansweredHelpOffersCount,
    relevantHelpOffersCount: relevant.length,
    unsettledRelevantCount: unsettled,
    hasWholeBeaconDoneSignal: hasExplicitWholeBeaconDoneSignal(state),
    enoughHelpOffered: authorMarkedEnoughHelp(state),
    hasSuccessfulHelpOfferResult: hasSuccessfulHelpOfferResult(state),
    requiresReviewWindow: expectedRequiresReviewWindowForState(state),
  );
}

extension BeaconViewClosureX on BeaconViewState {
  BeaconClosureReadiness get closureReadiness => computeClosureReadiness(this);

  ClosureActionPriority get closureActionPriority =>
      closureActionPriorityFor(
        closureReadiness,
        allowForceCloseWhenBlocked: kBeaconAllowForceCloseWhenBlocked,
      );
}
