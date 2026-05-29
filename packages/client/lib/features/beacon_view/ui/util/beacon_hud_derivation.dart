import 'package:flutter/foundation.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_chip_derivation.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_closure_readiness.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_now_detail_sheet.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Single-line (expandable in dashboard) “NOW” summary from existing beacon view state.
String beaconHudNowLine(L10n l10n, BeaconViewState state) {
  final beacon = state.beacon;
  final cue = state.beaconRoomCue;

  if (beacon.lifecycle == BeaconLifecycle.deleted) {
    return l10n.beaconHudBeaconUnavailable;
  }

  if (beacon.lifecycle == BeaconLifecycle.closed ||
      beacon.lifecycle == BeaconLifecycle.closedReviewComplete) {
    return l10n.beaconHudClosedSummary;
  }

  if (beacon.lifecycle == BeaconLifecycle.closedReviewOpen ||
      beacon.lifecycle == BeaconLifecycle.pendingReview) {
    return coordinationStatusLabel(l10n, beacon.coordinationStatus);
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

  final pub = beacon.lastPublicMeaningfulChange?.trim();
  if (pub != null && pub.isNotEmpty) {
    return pub;
  }

  final latest = latestTimelineUpdate(state.timeline);
  final updateContent = latest?.content.trim() ?? '';
  if (updateContent.isNotEmpty) {
    return updateContent;
  }

  final coordShort = coordinationStatusLabel(l10n, beacon.coordinationStatus);
  if (coordShort.isNotEmpty) {
    return coordShort;
  }

  final need = beacon.needSummary?.trim() ?? '';
  if (need.isNotEmpty) {
    return need;
  }

  return l10n.beaconHudNoCurrentLine;
}

/// Operational HUD NOW block: current line (or placeholder) plus optional blocker.
@immutable
class BeaconHudNowDisplay {
  const BeaconHudNowDisplay({
    required this.primaryText,
    this.blockerText,
    this.isPlaceholder = false,
  });

  final String primaryText;
  final String? blockerText;
  final bool isPlaceholder;
}

/// Operational HUD NOW row: current line or placeholder only (no read fallbacks).
BeaconHudNowDisplay beaconHudNowDisplay(L10n l10n, BeaconViewState state) {
  final beacon = state.beacon;
  final cue = state.beaconRoomCue;

  if (beacon.lifecycle == BeaconLifecycle.deleted) {
    return BeaconHudNowDisplay(primaryText: l10n.beaconHudBeaconUnavailable);
  }

  if (beacon.lifecycle == BeaconLifecycle.closed ||
      beacon.lifecycle == BeaconLifecycle.closedReviewComplete) {
    return BeaconHudNowDisplay(primaryText: l10n.beaconHudClosedSummary);
  }

  if (beacon.lifecycle == BeaconLifecycle.closedReviewOpen ||
      beacon.lifecycle == BeaconLifecycle.pendingReview) {
    return BeaconHudNowDisplay(
      primaryText: coordinationStatusLabel(l10n, beacon.coordinationStatus),
    );
  }

  final blockerTitle = cue?.openBlockerTitle?.trim();
  final blockerText = blockerTitle != null && blockerTitle.isNotEmpty
      ? l10n.beaconHudNowBlocked(blockerTitle)
      : null;

  final currentLine = cue?.currentLine.trim() ?? '';
  if (currentLine.isNotEmpty) {
    return BeaconHudNowDisplay(
      primaryText: currentLine,
      blockerText: blockerText,
    );
  }

  return BeaconHudNowDisplay(
    primaryText: l10n.beaconHudNoCurrentLine,
    blockerText: blockerText,
    isPlaceholder: true,
  );
}

/// Room pin NOW row from [BeaconRoomState] and optional open blocker item.
BeaconHudNowDisplay beaconRoomHudNowDisplay(
  L10n l10n, {
  required BeaconRoomState? roomState,
  CoordinationItem? openBlocker,
}) {
  final blockerTitle = roomState?.openBlockerTitle?.trim() ??
      openBlocker?.title.trim();
  final blockerText = blockerTitle != null && blockerTitle.isNotEmpty
      ? l10n.beaconHudNowBlocked(blockerTitle)
      : null;

  final currentLine = roomState?.currentLine.trim() ?? '';
  if (currentLine.isNotEmpty) {
    return BeaconHudNowDisplay(
      primaryText: currentLine,
      blockerText: blockerText,
    );
  }

  return BeaconHudNowDisplay(
    primaryText: l10n.beaconHudNoCurrentLine,
    blockerText: blockerText,
    isPlaceholder: true,
  );
}

bool beaconRoomShowsPinnedNow({
  required BeaconRoomState? roomState,
  CoordinationItem? openBlocker,
}) {
  final currentLine = roomState?.currentLine.trim() ?? '';
  if (currentLine.isNotEmpty) return true;
  final blockerTitle = roomState?.openBlockerTitle?.trim() ??
      openBlocker?.title.trim();
  return blockerTitle != null && blockerTitle.isNotEmpty;
}

BeaconNowDetailModel beaconNowDetailModelFromViewState(
  L10n l10n,
  BeaconViewState state, {
  bool canEdit = false,
  VoidCallback? onEdit,
}) {
  final beacon = state.beacon;
  final cue = state.beaconRoomCue;
  final nowDisplay = beaconHudNowDisplay(l10n, state);
  final currentLine = cue?.currentLine.trim() ?? '';

  final whatsNext = currentLine.isNotEmpty
      ? currentLine
      : (nowDisplay.isPlaceholder
          ? l10n.beaconHudNoCurrentLine
          : nowDisplay.primaryText);

  final roomLast = cue?.lastRoomMeaningfulChange?.trim();
  final pubLast = beacon.lastPublicMeaningfulChange?.trim();
  String? lastChange;
  if (roomLast != null && roomLast.isNotEmpty) {
    lastChange = roomLast;
  } else if (pubLast != null && pubLast.isNotEmpty) {
    lastChange = pubLast;
  }

  final isReviewLifecycle =
      beacon.lifecycle == BeaconLifecycle.closedReviewOpen ||
      beacon.lifecycle == BeaconLifecycle.pendingReview;

  return BeaconNowDetailModel(
    whatsNextText: whatsNext,
    isPlaceholder: currentLine.isEmpty && nowDisplay.isPlaceholder,
    blockerTitle: cue?.openBlockerTitle?.trim(),
    blockerItem: state.openCoordinationBlocker,
    publicStatus:
        beacon.lifecycle == BeaconLifecycle.open ? beacon.publicStatus : null,
    coordinationStatus:
        isReviewLifecycle ? beacon.coordinationStatus : null,
    lifecycle: beacon.lifecycle,
    lastChangeText: lastChange,
    canEdit: canEdit,
    onEdit: onEdit,
  );
}

BeaconNowDetailModel beaconNowDetailModelFromRoom(
  L10n l10n, {
  required BeaconRoomState? roomState,
  CoordinationItem? openCoordinationBlocker,
  bool canEdit = false,
  VoidCallback? onEdit,
}) {
  final currentLine = roomState?.currentLine.trim() ?? '';
  final blockerTitle = roomState?.openBlockerTitle?.trim() ??
      openCoordinationBlocker?.title.trim();
  final whatsNext =
      currentLine.isNotEmpty ? currentLine : l10n.beaconHudNoCurrentLine;

  return BeaconNowDetailModel(
    whatsNextText: whatsNext,
    isPlaceholder: currentLine.isEmpty,
    blockerTitle: blockerTitle != null && blockerTitle.isNotEmpty
        ? blockerTitle
        : null,
    blockerItem: openCoordinationBlocker,
    lastChangeText: roomState?.lastRoomMeaningfulChange?.trim(),
    canEdit: canEdit,
    onEdit: onEdit,
  );
}

/// User-relative “YOU” instruction line (no new server fields).
String beaconHudYouLine(L10n l10n, BeaconViewState state) {
  final beacon = state.beacon;

  if (beacon.lifecycle == BeaconLifecycle.deleted) {
    return l10n.beaconHudYouNoActionAvailable;
  }

  if (beacon.lifecycle == BeaconLifecycle.closed ||
      beacon.lifecycle == BeaconLifecycle.closedReviewComplete) {
    return l10n.beaconHudClosedSummary;
  }

  if (state.isBeaconMine) {
    if (state.unansweredHelpOffersCount > 0) {
      return l10n.beaconHudYouAuthorReview(state.unansweredHelpOffersCount);
    }
    final blockerTitle = state.beaconRoomCue?.openBlockerTitle?.trim();
    if (blockerTitle != null && blockerTitle.isNotEmpty) {
      return l10n.beaconHudYouAuthorResolveBlocker;
    }
    if (beacon.lifecycle == BeaconLifecycle.open) {
      switch (computeClosureReadiness(state)) {
        case BeaconClosureReadiness.readyToClose:
          return l10n.beaconHudYouAuthorReadyToClose;
        case BeaconClosureReadiness.waitingForReview:
          return l10n.beaconHudYouAuthorReviewBeforeClose;
        case BeaconClosureReadiness.premature:
          return l10n.beaconHudYouAuthorCoordinationActive;
        case BeaconClosureReadiness.blocked:
          return l10n.beaconHudYouAuthorResolveBlocker;
        case BeaconClosureReadiness.notCloseable:
          break;
      }
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

  if (beacon.lifecycle == BeaconLifecycle.open &&
      !state.isHelpOffered &&
      beacon.allowsNewHelpOfferAsNonAuthor) {
    return l10n.beaconHudYouCanOfferHelp;
  }

  return l10n.beaconHudYouNoAction;
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

/// Expanded NOW body for the Status lens (includes plan vs blocker vs cue).
String beaconHudNowExpandedBody(L10n l10n, BeaconViewState state) {
  final beacon = state.beacon;
  final cue = state.beaconRoomCue;
  final lines = <String>[];

  if (beacon.lifecycle == BeaconLifecycle.deleted) {
    return l10n.beaconHudBeaconUnavailable;
  }

  final blockerTitle = cue?.openBlockerTitle?.trim();
  if (blockerTitle != null && blockerTitle.isNotEmpty) {
    lines.add(l10n.beaconHudNowBlocked(blockerTitle));
  }

  final currentLine = cue?.currentLine.trim() ?? '';
  if (currentLine.isNotEmpty) {
    lines.add(currentLine);
  }

  final roomCue = cue?.lastRoomMeaningfulChange?.trim();
  if (roomCue != null && roomCue.isNotEmpty) {
    lines.add(roomCue);
  }

  final pub = beacon.lastPublicMeaningfulChange?.trim();
  if (pub != null && pub.isNotEmpty) {
    lines.add(pub);
  }

  final latest = latestTimelineUpdate(state.timeline);
  final updateContent = latest?.content.trim() ?? '';
  if (updateContent.isNotEmpty) {
    lines.add(updateContent);
  }

  if (lines.isEmpty) {
    return beaconHudNowLine(l10n, state);
  }

  return lines.toSet().join('\n\n');
}
