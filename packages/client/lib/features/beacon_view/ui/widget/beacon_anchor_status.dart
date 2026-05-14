import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_closure_readiness.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// Semantic tone for the operational "anchor" status line (coordination + help offers).
TenturaTone beaconAnchorStatusTone(BeaconCoordinationStatus s) => switch (s) {
      BeaconCoordinationStatus.noHelpOffersYet => TenturaTone.neutral,
      BeaconCoordinationStatus.helpOffersWaitingForReview => TenturaTone.info,
      BeaconCoordinationStatus.moreOrDifferentHelpNeeded => TenturaTone.warn,
      BeaconCoordinationStatus.enoughHelpOffered => TenturaTone.good,
    };

/// Localized anchor line: coordination label · help offers fragment.
String beaconAnchorStatusLine(
  L10n l10n,
  Beacon beacon,
  int activeHelpOfferCount,
) {
  final coord = coordinationStatusLabel(l10n, beacon.coordinationStatus);
  final helpOfferedPart = activeHelpOfferCount == 0
      ? l10n.beaconHeaderNoHelpOffers
      : l10n.beaconHeaderHelpOffersCount(activeHelpOfferCount);
  return '$coord · $helpOfferedPart';
}

/// Terse anchor line for compact surfaces (e.g. AppBar): ALL-CAPS code · count.
String beaconAnchorStatusLineShort(
  Beacon beacon,
  int activeHelpOfferCount,
) =>
    switch (beacon.coordinationStatus) {
      BeaconCoordinationStatus.noHelpOffersYet => 'IDLE',
      BeaconCoordinationStatus.helpOffersWaitingForReview =>
        activeHelpOfferCount > 0 ? 'REVIEW · $activeHelpOfferCount' : 'REVIEW',
      BeaconCoordinationStatus.moreOrDifferentHelpNeeded =>
        activeHelpOfferCount > 0 ? 'GAP · $activeHelpOfferCount' : 'GAP',
      BeaconCoordinationStatus.enoughHelpOffered =>
        activeHelpOfferCount > 0 ? 'OK · $activeHelpOfferCount' : 'OK',
    };

/// Compact state tokens for the beacon HUD (newest / highest-signal first; UI may cap count).
List<String> buildBeaconHudStateTokens({
  required L10n l10n,
  required Beacon beacon,
  required int activeHelpOfferCount,
  required int needCoordinationCount,
  BeaconRoomState? cue,
  BeaconClosureReadiness? authorClosureReadiness,
}) {
  switch (beacon.lifecycle) {
    case BeaconLifecycle.deleted:
      return [l10n.beaconHudLifecycleDeleted];
    case BeaconLifecycle.closed:
    case BeaconLifecycle.closedReviewComplete:
      return [l10n.beaconHudLifecycleClosed];
    case BeaconLifecycle.closedReviewOpen:
    case BeaconLifecycle.pendingReview:
      return [l10n.beaconHudReviewOpen];
    case BeaconLifecycle.draft:
      return [l10n.beaconLifecycleDraft];
    case BeaconLifecycle.open:
      break;
  }

  final out = <String>[];
  final blockerTitle = cue?.openBlockerTitle?.trim();
  final hasBlocker = blockerTitle != null && blockerTitle.isNotEmpty;

  if (hasBlocker) {
    out.add(l10n.beaconHudBlocked);
    final t = blockerTitle;
    out.add(t.length > 36 ? '${t.substring(0, 33)}…' : t);
  }

  final closure = authorClosureReadiness;
  if (closure == BeaconClosureReadiness.readyToClose) {
    out.add(l10n.beaconHudTokenReadyToClose);
  } else if (closure == BeaconClosureReadiness.waitingForReview) {
    out.add(l10n.beaconHudTokenReviewBeforeClose);
  } else if (closure == BeaconClosureReadiness.blocked && !hasBlocker) {
    out.add(l10n.beaconHudTokenClosureBlocked);
  }

  final enough =
      beacon.coordinationStatus == BeaconCoordinationStatus.enoughHelpOffered;
  if (enough) {
    out.add(l10n.beaconHudEnoughHelp);
  } else if (!hasBlocker) {
    out.add(l10n.beaconHudLifecycleActive);
  }

  if (needCoordinationCount > 0) {
    out.add(l10n.beaconHudTokenNeedCoordCount(needCoordinationCount));
  }

  if (activeHelpOfferCount > 0 && !enough) {
    out.add(l10n.beaconHudTokenHelpOfferedCount(activeHelpOfferCount));
  }

  final end = beacon.endAt;
  if (end != null) {
    out.add(l10n.beaconChipDeadlineOn(dateFormatYMD(end)));
  }

  return out;
}
