import '../entity/beacon.dart';
import '../entity/beacon_coordination_phase.dart';
import '../entity/open_blocker_cue.dart';

/// Humble object for [deriveBeaconCoordinationPhase].
class BeaconCoordinationPhaseInput {
  const BeaconCoordinationPhaseInput({
    required this.beacon,
    required this.tier,
    required this.now,
    this.hasOpenBlocker = false,
    this.hasUnreviewedOffers = false,
    this.hasOpenRoomAsks = false,
    this.openBlocker,
    this.lastActivityAt,
  });

  final Beacon beacon;
  final BeaconVisibilityTier tier;
  final DateTime now;
  final bool hasOpenBlocker;
  final bool hasUnreviewedOffers;
  final bool hasOpenRoomAsks;
  final OpenBlockerCue? openBlocker;

  /// Latest meaningful activity (beacon update, room change, etc.) for freshness.
  final DateTime? lastActivityAt;
}
