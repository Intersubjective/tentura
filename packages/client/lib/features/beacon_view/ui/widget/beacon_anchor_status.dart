import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura/domain/coordination/derive_beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/presenter/beacon_phase_input_builders.dart';
import 'package:tentura/ui/presenter/beacon_phase_presenter.dart';

/// Semantic tone for coordination status chips (legacy surfaces).
TenturaTone beaconAnchorStatusTone(BeaconStatus s) => switch (s) {
      BeaconStatus.open => TenturaTone.neutral,
      BeaconStatus.needsMoreHelp => TenturaTone.warn,
      BeaconStatus.enoughHelp => TenturaTone.good,
      _ => TenturaTone.neutral,
    };

/// Shared operational status for beacon detail app bar subtitle.
final class BeaconViewStatusSlots {
  const BeaconViewStatusSlots({
    required this.presentation,
  });

  final BeaconPhaseStatusPresentation presentation;

  String get slot1 => presentation.slot1;
  String get slot2 => presentation.slot2 ?? '';
  TenturaTone get tone => presentation.slot1Tone;
  String get displayLine => presentation.statusLine;
}

/// Shared phase-based status from [BeaconViewState] (identical per visibility tier).
BeaconViewStatusSlots beaconViewStatusSlots(
  L10n l10n,
  BeaconViewState state, {
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  final beacon = state.beacon;

  if (beacon.status == BeaconStatus.deleted) {
    return BeaconViewStatusSlots(
      presentation: BeaconPhaseStatusPresentation(
        slot1: l10n.beaconHudBeaconUnavailable,
        slot1Tone: TenturaTone.neutral,
      ),
    );
  }

  final input = beaconPhaseInputFromViewState(state, now: clock);
  final result = deriveBeaconCoordinationPhase(input);
  final pres = formatBeaconPhaseStatus(l10n, result, now: clock);

  assert(pres.statusLine.trim().isNotEmpty, 'phase status must never be empty');

  return BeaconViewStatusSlots(presentation: pres);
}

/// Localized anchor line: coordination label · help offers fragment.
String beaconAnchorStatusLine(
  L10n l10n,
  Beacon beacon,
  int activeHelpOfferCount,
) {
  final coord = coordinationStatusLabel(l10n, beacon.status);
  final helpOfferedPart = activeHelpOfferCount == 0
      ? l10n.beaconHeaderNoHelpOffers
      : l10n.beaconHeaderHelpOffersCount(activeHelpOfferCount);
  return '$coord · $helpOfferedPart';
}
