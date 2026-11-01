import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/presenter/beacon_hud_author_action.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/util/beacon_hud_now_display.dart';

/// Single-line (expandable in dashboard) “NOW” summary from existing beacon view state.
String beaconHudNowLine(L10n l10n, BeaconViewState state) {
  final beacon = state.beacon;
  final cue = state.beaconRoomCue;

  if (beacon.status == BeaconStatus.deleted) {
    return l10n.beaconHudBeaconUnavailable;
  }

  if (beacon.status == BeaconStatus.closed ||
      beacon.status == BeaconStatus.cancelled) {
    return l10n.beaconHudClosedSummary;
  }

  if (beacon.status == BeaconStatus.reviewOpen) {
    return coordinationStatusLabel(l10n, beacon.status);
  }

  final blockerTitle = cue?.openBlockerTitle?.trim();
  if (blockerTitle != null && blockerTitle.isNotEmpty) {
    return l10n.beaconHudNowBlocked(blockerTitle);
  }

  final currentLine = cue?.currentLine.trim() ?? '';
  if (currentLine.isNotEmpty) {
    return currentLine;
  }

  final roomCue = cue?.lastRoomMeaningfulChange?.trim();
  if (roomCue != null && roomCue.isNotEmpty) {
    return roomCue;
  }

  final coordShort = coordinationStatusLabel(l10n, beacon.status);
  if (coordShort.isNotEmpty) {
    return coordShort;
  }

  final description = beacon.description.trim();
  if (description.isNotEmpty) {
    return description.split('\n').first.trim();
  }

  return l10n.beaconHudNoCurrentLine;
}

/// Operational HUD NOW row: current line or placeholder only (no read fallbacks).
BeaconHudNowDisplay beaconHudNowDisplay(L10n l10n, BeaconViewState state) {
  final beacon = state.beacon;
  final cue = state.beaconRoomCue;

  if (beacon.status == BeaconStatus.deleted) {
    return BeaconHudNowDisplay(primaryText: l10n.beaconHudBeaconUnavailable);
  }

  if (beacon.status == BeaconStatus.closed ||
      beacon.status == BeaconStatus.cancelled) {
    return BeaconHudNowDisplay(primaryText: l10n.beaconHudClosedSummary);
  }

  if (beacon.status == BeaconStatus.reviewOpen) {
    return BeaconHudNowDisplay(
      primaryText: coordinationStatusLabel(l10n, beacon.status),
    );
  }

  final blockerTitle = cue?.openBlockerTitle?.trim();
  final blockerText = blockerTitle != null && blockerTitle.isNotEmpty
      ? l10n.beaconHudNowBlocked(blockerTitle)
      : null;

  final currentLine = cue?.currentLine.trim() ?? '';
  if (currentLine.isNotEmpty) {
    return BeaconHudNowDisplay(
      primaryText: clipBeaconRoomCurrentLine(currentLine),
      blockerText: blockerText,
    );
  }

  return BeaconHudNowDisplay(
    primaryText: l10n.beaconHudNoCurrentLine,
    blockerText: blockerText,
    isPlaceholder: true,
  );
}

/// User-relative “YOU” instruction line (no new server fields).
String beaconHudYouLine(L10n l10n, BeaconViewState state) {
  final beacon = state.beacon;

  if (beacon.status == BeaconStatus.deleted) {
    return l10n.beaconHudYouNoActionAvailable;
  }

  if (beacon.status == BeaconStatus.closed ||
      beacon.status == BeaconStatus.cancelled) {
    return l10n.beaconHudClosedSummary;
  }

  if (state.isBeaconMine) {
    final act = deriveBeaconHudAuthorAction(state);
    if (act == null) {
      if (beacon.status == BeaconStatus.reviewOpen) {
        return l10n.beaconHudWaitingForReviews;
      }
      if (beacon.viewerCanForward) {
        return _everyForwardDeclined(state)
            ? l10n.beaconHudYouForwardAfterDecline
            : l10n.beaconHudYouForward;
      }
      if (authorHudShowsStatusOverflowFallback(state)) {
        return l10n.beaconHudYouChangeStatusInOverflow;
      }
    } else {
      return _authorYouSituationLine(l10n, state, act);
    }
    return l10n.beaconHudYouAuthorIdle;
  }

  final myMove = _myNextMoveText(state);
  if (myMove != null && myMove.isNotEmpty) {
    return l10n.beaconHudNextMovePrefix(myMove);
  }

  if (state.isHelpOffered) {
    return l10n.beaconHudYouHelpOffered;
  }

  if (state.inboxStatus == InboxItemStatus.needsMe) {
    return l10n.beaconHudYouAskedToHelp;
  }

  if (state.inboxStatus == InboxItemStatus.watching) {
    return l10n.beaconHudYouWatching;
  }

  if (beacon.status == BeaconStatus.open &&
      !state.isHelpOffered &&
      beacon.allowsNewHelpOfferAsNonAuthor) {
    return l10n.beaconHudYouCanOfferHelp;
  }

  return l10n.beaconHudYouNoAction;
}

/// #486: the author forwarded to someone and every live forward was declined.
bool _everyForwardDeclined(BeaconViewState state) {
  final live = state.myForwards.where(
    (e) => e.sender.id == state.myProfile.id && !e.isCancelled,
  );
  return live.isNotEmpty && live.every((e) => e.recipientRejected);
}

String _authorYouSituationLine(
  L10n l10n,
  BeaconViewState state,
  BeaconHudAuthorAction act,
) {
  return switch (act) {
    BeaconHudAuthorAction.reviewOffers =>
      l10n.beaconHudYouAuthorReview(state.unansweredHelpOffersCount),
    BeaconHudAuthorAction.resolveBlocker => () {
      final blockerTitle = state.beaconRoomCue?.openBlockerTitle?.trim();
      if (blockerTitle != null && blockerTitle.isNotEmpty) {
        return blockerTitle;
      }
      return l10n.beaconHudYouAuthorResolveBlocker;
    }(),
    BeaconHudAuthorAction.markEnoughHelp =>
      l10n.beaconHudYouAuthorCoordinationActive,
    BeaconHudAuthorAction.wrapUpForReview ||
    BeaconHudAuthorAction.sumUp ||
    BeaconHudAuthorAction.closeNow =>
      l10n.beaconHudYouAuthorReadyToClose,
  };
}

String? _myNextMoveText(BeaconViewState state) {
  final id = state.myProfile.id;
  if (id.isEmpty) return null;
  for (final p in state.roomParticipants) {
    if (p.userId == id) {
      final t = p.nextMoveText?.trim();
      if (t != null && t.isNotEmpty) {
        return t;
      }
    }
  }
  return null;
}
