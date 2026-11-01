import 'package:tentura/domain/coordination/beacon_coordination_phase_input.dart';
import 'package:tentura/domain/coordination/beacon_has_unreviewed_offers.dart';
import 'package:tentura/domain/coordination/derive_beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/open_blocker_cue.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';

BeaconCoordinationPhaseInput beaconPhaseInputFromViewState(
  BeaconViewState state, {
  DateTime? now,
}) {
  final beacon = state.beacon;
  final cue = state.beaconRoomCue;
  final tier = state.canCoordinateInBeaconRoom
      ? BeaconVisibilityTier.coordination
      : BeaconVisibilityTier.public;

  final blockerTitle =
      cue?.openBlockerTitle?.trim() ??
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
