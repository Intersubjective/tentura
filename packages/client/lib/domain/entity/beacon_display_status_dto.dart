import 'package:tentura/domain/entity/beacon_coordination_phase.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

/// Server-derived display projection (`BeaconDisplayStatus` V2 query).
class BeaconDisplayStatusDto {
  const BeaconDisplayStatusDto({
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
  final BeaconCoordinationPhase phase;
  final BeaconPhasePrimaryAction suggestedAction;
  final BeaconPhaseSlot2Kind slot2Kind;
  final BeaconDisplayTier tier;
  final DateTime? reviewClosesAt;
  final DateTime? lastActivityAt;
  final DateTime? lifecycleEndedAt;

  BeaconCoordinationPhaseResult toPhaseResult() => BeaconCoordinationPhaseResult(
        phase: phase,
        slot2Kind: slot2Kind,
        suggestedAction: suggestedAction,
        rowHarmony: BeaconPhaseRowHarmony.empty,
        reviewClosesAt: reviewClosesAt,
        lastActivityAt: lastActivityAt,
        lifecycleEndedAt: lifecycleEndedAt,
      );
}

/// Maps server tier string to client enum.
enum BeaconDisplayTier { coordination, public }

BeaconCoordinationPhase _phaseFromName(String name) =>
    BeaconCoordinationPhase.values.byName(name);

BeaconPhasePrimaryAction _actionFromName(String name) =>
    BeaconPhasePrimaryAction.values.byName(name);

BeaconPhaseSlot2Kind _slot2FromName(String name) =>
    BeaconPhaseSlot2Kind.values.byName(name);

BeaconDisplayTier _tierFromName(String name) =>
    BeaconDisplayTier.values.byName(name);

BeaconDisplayStatusDto beaconDisplayStatusFromGql(Map<String, dynamic> json) {
  return BeaconDisplayStatusDto(
    beaconId: json['beaconId'] as String,
    status: BeaconStatus.fromSmallint(json['status'] as int),
    phase: _phaseFromName(json['phase'] as String),
    suggestedAction: _actionFromName(json['suggestedAction'] as String),
    slot2Kind: _slot2FromName(json['slot2Kind'] as String),
    tier: _tierFromName(json['tier'] as String),
    reviewClosesAt: _parseOpt(json['reviewClosesAt'] as String?),
    lastActivityAt: _parseOpt(json['lastActivityAt'] as String?),
    lifecycleEndedAt: _parseOpt(json['lifecycleEndedAt'] as String?),
  );
}

DateTime? _parseOpt(String? raw) =>
    raw == null || raw.isEmpty ? null : DateTime.tryParse(raw)?.toUtc();
