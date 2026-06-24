import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura/domain/coordination/derive_beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
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

TenturaTone coordinationResponseTone(CoordinationResponseType r) => switch (r) {
      CoordinationResponseType.useful => TenturaTone.good,
      CoordinationResponseType.overlapping => TenturaTone.info,
      CoordinationResponseType.needDifferentSkill => TenturaTone.danger,
      CoordinationResponseType.needCoordination => TenturaTone.info,
      CoordinationResponseType.notSuitable => TenturaTone.danger,
    };

/// Shared operational status for beacon detail app bar subtitle.
final class BeaconViewStatusSlots {
  const BeaconViewStatusSlots({
    required this.slot1,
    required this.slot2,
    required this.tone,
  });

  final String slot1;
  final String slot2;
  final TenturaTone tone;

  bool get isEmpty => slot1.trim().isEmpty && slot2.trim().isEmpty;

  String get displayLine {
    final s1 = slot1.trim();
    final s2 = slot2.trim();
    if (s1.isEmpty && s2.isEmpty) return '';
    if (s1.isEmpty) return s2;
    if (s2.isEmpty) return s1;
    return '$s1 · $s2';
  }
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
      slot1: l10n.beaconHudBeaconUnavailable,
      slot2: '',
      tone: TenturaTone.neutral,
    );
  }

  final input = beaconPhaseInputFromViewState(state, now: clock);
  final result = deriveBeaconCoordinationPhase(input);
  final pres = formatBeaconPhaseStatus(l10n, result, now: clock);

  assert(pres.statusLine.trim().isNotEmpty, 'phase status must never be empty');

  return BeaconViewStatusSlots(
    slot1: pres.statusLine,
    slot2: '',
    tone: pres.tone,
  );
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
