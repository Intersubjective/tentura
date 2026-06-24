import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/domain/coordination/derive_beacon_display_status.dart';

class BeaconDisplayStatus {
  const BeaconDisplayStatus({
    required this.beaconId,
    required this.status,
    required this.phase,
    required this.suggestedAction,
    required this.slot2Kind,
    required this.tier,
    this.reviewClosesAt,
    this.lastActivityAt,
    this.lifecycleEndedAt,
  });

  final String beaconId;
  final BeaconStatus status;
  final BeaconDisplayPhase phase;
  final BeaconDisplayPrimaryAction suggestedAction;
  final BeaconDisplaySlot2Kind slot2Kind;
  final BeaconDisplayTier tier;
  final DateTime? reviewClosesAt;
  final DateTime? lastActivityAt;
  final DateTime? lifecycleEndedAt;
}
