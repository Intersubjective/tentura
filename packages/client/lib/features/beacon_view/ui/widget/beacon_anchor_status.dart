import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura/domain/coordination/derive_beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/presenter/beacon_phase_input_builders.dart';
import 'package:tentura/ui/presenter/beacon_phase_presenter.dart';

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
  final phasePres = formatBeaconPhaseStatus(l10n, result, now: clock);
  final offerCue = _pendingOfferCue(l10n, state, result);
  // #636: a pending offer is a per-viewer cue in slot2; the shared status
  // verb (slot1) stays as derived — the first offer does not change it (#504).
  final pres = offerCue == null
      ? phasePres
      : BeaconPhaseStatusPresentation(
          slot1: phasePres.slot1,
          slot2: offerCue,
          slot1Tone: phasePres.slot1Tone,
          slot2Tone: TenturaTone.info,
        );

  assert(pres.statusLine.trim().isNotEmpty, 'phase status must never be empty');

  return BeaconViewStatusSlots(presentation: pres);
}

/// #636: the author sees how many offers wait for review; the helper whose
/// own offer still waits sees "Offer sent". Gone once the offer is accepted,
/// declined or withdrawn. A blocker cue keeps slot2.
String? _pendingOfferCue(
  L10n l10n,
  BeaconViewState state,
  BeaconCoordinationPhaseResult result,
) {
  if (!state.beacon.status.isOpenFamily) return null;
  if (result.slot2Kind == BeaconPhaseSlot2Kind.blockerNeedsClearing) {
    return null;
  }
  if (state.isBeaconMine) {
    // One number everywhere (#636): the HUD "Review N offers", the YOU line
    // and My Work (#710) count the same unanswered ordinary offers; a backup
    // kept on standby never gets a response and is not counted.
    final count = state.unansweredHelpOffersCount;
    return count > 0 ? l10n.beaconPhaseOffersToReview(count) : null;
  }
  final mine = state.myActiveHelpOffer;
  if (mine != null && _isUnansweredOffer(state, mine)) {
    return l10n.beaconPhaseOfferSent;
  }
  return null;
}

/// The viewer's own offer still waits for an answer — the same rule as
/// [BeaconViewState.unansweredHelpOffersCount]. A standby backup (#710) never
/// gets a coordination row, so it never reads "Offer sent".
bool _isUnansweredOffer(BeaconViewState state, TimelineHelpOffer offer) =>
    !offer.isWithdrawn &&
    !offer.isBackup &&
    offer.coordinationResponse == null &&
    offer.roomAccess != RoomAccessBits.admitted &&
    !state.roomParticipants.any(
      (p) =>
          p.userId == offer.user.id && p.roomAccess == RoomAccessBits.admitted,
    );
