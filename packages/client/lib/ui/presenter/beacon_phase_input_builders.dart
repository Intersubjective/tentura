import 'package:tentura/domain/coordination/beacon_coordination_phase_input.dart';
import 'package:tentura/domain/coordination/beacon_has_unreviewed_offers.dart';
import 'package:tentura/domain/coordination/derive_beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/coordination_responsibility.dart';
import 'package:tentura/domain/entity/open_blocker_cue.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_room_card_hints.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';

BeaconCoordinationPhaseInput beaconPhaseInputFromViewState(
  BeaconViewState state, {
  DateTime? now,
}) {
  final beacon = state.beacon;
  final cue = state.beaconRoomCue;
  final tier = state.canCoordinateInBeaconRoom
      ? BeaconVisibilityTier.coordination
      : BeaconVisibilityTier.public;

  final blockerTitle = cue?.openBlockerTitle?.trim() ??
      state.openCoordinationBlocker?.title.trim() ??
      '';
  final hasOpenBlocker = blockerTitle.isNotEmpty;

  final openBlocker = _openBlockerFromViewState(state, blockerTitle);

  final resp = state.youResponsibility;
  final hasOpenRoomAsks = resp != null && resp.askOpen > 0;

  return buildBeaconCoordinationPhaseInput(
    beacon: beacon,
    tier: tier,
    now: now,
    hasOpenBlocker: hasOpenBlocker,
    hasUnreviewedOffers: beaconHasUnreviewedOffers(beacon),
    hasOpenRoomAsks: hasOpenRoomAsks,
    openBlocker: openBlocker,
    lastActivityAt: beacon.updatedAt,
  );
}

OpenBlockerCue? _openBlockerFromViewState(
  BeaconViewState state,
  String title,
) {
  if (title.isEmpty) return null;
  final item = state.openCoordinationBlocker;
  if (item == null) {
    return OpenBlockerCue(
      creatorId: '',
      title: title,
      raisedAt: state.beacon.updatedAt,
    );
  }
  final target = item.targetPersonId?.trim() ?? '';
  final creatorId = item.creatorId;
  final responsible = OpenBlockerCue.resolveResponsibleUserId(
    creatorId: creatorId,
    targetPersonId: target.isEmpty ? null : target,
  );
  return OpenBlockerCue(
    creatorId: creatorId,
    targetPersonId: target,
    responsibleUserId: responsible,
    title: title,
    raisedAt: item.createdAt,
  );
}

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
  if (responsibility != null && responsibility.blockerOpen > 0) {
    return true;
  }
  return viewerIsPersonallyResponsibleForBlocker(
    openBlocker: openBlocker,
    viewerUserId: viewerUserId,
  );
}
