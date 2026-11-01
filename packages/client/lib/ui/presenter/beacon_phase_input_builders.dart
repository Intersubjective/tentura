import 'package:tentura/domain/coordination/beacon_coordination_phase_input.dart';
import 'package:tentura/domain/coordination/beacon_has_unreviewed_offers.dart';
import 'package:tentura/domain/coordination/derive_beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/coordination_responsibility.dart';
import 'package:tentura/domain/entity/open_blocker_cue.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_room_card_hints.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';

BeaconCoordinationPhaseInput beaconPhaseInputFromMyWorkCard(
  MyWorkCardViewModel vm, {
  DateTime? now,
}) {
  final beacon = vm.beacon;
  final openBlocker = vm.roomOpenBlocker;
  final hasOpenBlocker = openBlocker != null && openBlocker.title.trim().isNotEmpty;
  final resp = vm.youResponsibility;
  final hasOpenRoomAsks = resp != null && resp.askOpen > 0;

  return buildBeaconCoordinationPhaseInput(
    beacon: beacon,
    tier: BeaconVisibilityTier.coordination,
    now: now,
    hasOpenBlocker: hasOpenBlocker,
    hasUnreviewedOffers: vm.showReviewHelpOffersCta ||
        beaconHasUnreviewedOffers(beacon),
    hasOpenRoomAsks: hasOpenRoomAsks,
    openBlocker: openBlocker,
    lastActivityAt: beacon.updatedAt,
  );
}

BeaconCoordinationPhaseInput beaconPhaseInputFromInbox({
  required Beacon beacon,
  InboxRoomCardHints? roomHints,
  DateTime? now,
}) {
  final hints = roomHints;
  final tier = hints != null && hints.isRoomMember
      ? BeaconVisibilityTier.coordination
      : BeaconVisibilityTier.public;

  final openBlocker = hints?.openBlocker;
  final legacyTitle = hints?.openBlockerTitle.trim() ?? '';
  final hasOpenBlocker = openBlocker != null
      ? openBlocker.title.trim().isNotEmpty
      : legacyTitle.isNotEmpty;

  return buildBeaconCoordinationPhaseInput(
    beacon: beacon,
    tier: tier,
    now: now,
    hasOpenBlocker: hasOpenBlocker,
    hasUnreviewedOffers: beaconHasUnreviewedOffers(beacon),
    openBlocker: openBlocker ??
        (legacyTitle.isEmpty
            ? null
            : OpenBlockerCue(
                creatorId: '',
                title: legacyTitle,
                raisedAt: beacon.updatedAt,
              )),
    lastActivityAt: beacon.updatedAt,
  );
}

bool viewerIsPersonallyResponsibleForBlocker({
  required OpenBlockerCue? openBlocker,
  required String viewerUserId,
}) {
  if (openBlocker == null) return false;
  if (openBlocker.responsibleUserId.isNotEmpty) {
    return openBlocker.isResponsible(viewerUserId);
  }
  return false;
}

bool blockerOpenTargetsViewer({
  required CoordinationResponsibility? responsibility,
  required OpenBlockerCue? openBlocker,
  required String viewerUserId,
}) {
  // Responsibility counts can outlive the blocker cue after review submission.
  if (openBlocker == null) return false;

  if (responsibility != null && responsibility.blockerOpen > 0) {
    return true;
  }
  return viewerIsPersonallyResponsibleForBlocker(
    openBlocker: openBlocker,
    viewerUserId: viewerUserId,
  );
}
