import 'package:tentura/domain/coordination/derive_beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/open_blocker_cue.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/presenter/beacon_phase_input_builders.dart';
import 'package:tentura/ui/presenter/beacon_phase_presenter.dart';

/// Resolves gated primary CTA label for My Work authored cards.
String? myWorkPhasePrimaryCtaLabel({
  required L10n l10n,
  required MyWorkCardViewModel vm,
  required String viewerUserId,
}) {
  final input = beaconPhaseInputFromMyWorkCard(vm);
  final result = deriveBeaconCoordinationPhase(input);
  final isAuthor = vm.beacon.author.id == viewerUserId;
  final action = resolveEffectivePrimaryAction(
    suggested: result.suggestedAction,
    isAuthor: isAuthor,
    isAuthorOrSteward: isAuthor,
    canCoordinateInRoom: true,
    isPersonallyResponsibleForBlocker: viewerIsPersonallyResponsibleForBlocker(
      openBlocker: vm.roomOpenBlocker,
      viewerUserId: viewerUserId,
    ),
    canOfferHelp: false,
    canNavigateRoom: true,
  );
  return formatBeaconPhasePrimaryCtaLabel(l10n, action, isAuthor: isAuthor);
}

/// Resolves gated primary CTA label for beacon detail HUD.
String? beaconHudPhasePrimaryCtaLabel({
  required L10n l10n,
  required BeaconViewState state,
  required String viewerUserId,
}) {
  final input = beaconPhaseInputFromViewState(state);
  final result = deriveBeaconCoordinationPhase(input);
  final action = resolveEffectivePrimaryAction(
    suggested: result.suggestedAction,
    isAuthor: state.isBeaconMine,
    isAuthorOrSteward: state.isAuthorOrSteward,
    canCoordinateInRoom: state.canCoordinateInBeaconRoom,
    isPersonallyResponsibleForBlocker: viewerIsPersonallyResponsibleForBlocker(
      openBlocker: input.openBlocker,
      viewerUserId: viewerUserId,
    ),
    canOfferHelp: _canOfferHelp(state),
    canNavigateRoom: state.canNavigateBeaconRoom,
  );
  return formatBeaconPhasePrimaryCtaLabel(
    l10n,
    action,
    isAuthor: state.isBeaconMine,
  );
}

bool _canOfferHelp(BeaconViewState state) {
  final b = state.beacon;
  return b.lifecycle == BeaconLifecycle.open &&
      !state.isHelpOffered &&
      b.allowsNewHelpOfferAsNonAuthor;
}

BeaconPhasePrimaryAction myWorkEffectivePrimaryAction({
  required MyWorkCardViewModel vm,
  required String viewerUserId,
}) {
  final input = beaconPhaseInputFromMyWorkCard(vm);
  final result = deriveBeaconCoordinationPhase(input);
  final isAuthor = vm.beacon.author.id == viewerUserId;
  return resolveEffectivePrimaryAction(
    suggested: result.suggestedAction,
    isAuthor: isAuthor,
    isAuthorOrSteward: isAuthor,
    canCoordinateInRoom: true,
    isPersonallyResponsibleForBlocker: viewerIsPersonallyResponsibleForBlocker(
      openBlocker: vm.roomOpenBlocker,
      viewerUserId: viewerUserId,
    ),
    canOfferHelp: false,
    canNavigateRoom: true,
  );
}

OpenBlockerCue? openBlockerFromViewState(BeaconViewState state) =>
    beaconPhaseInputFromViewState(state).openBlocker;
