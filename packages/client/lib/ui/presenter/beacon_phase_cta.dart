import 'package:tentura/domain/coordination/derive_beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/beacon_coordination_phase.dart';
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
