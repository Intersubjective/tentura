import 'package:logging/logging.dart';
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
    this.canCancel = false,
    this.canDelete = false,
    this.everAcknowledgedCommitterCount = 0,
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
  final bool canCancel;
  final bool canDelete;
  final int everAcknowledgedCommitterCount;

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

final _logger = Logger('BeaconDisplayStatusDto');

/// Server-sent enums must never fail the whole list: unknown names log once
/// and fall back to a safe default.
T _enumFromName<T extends Enum>(
  List<T> values,
  String name,
  T fallback,
  String field,
) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  _logger.warning('Unknown $field "$name", falling back to ${fallback.name}');
  return fallback;
}

BeaconCoordinationPhase _phaseFromName(String name) => _enumFromName(
  BeaconCoordinationPhase.values,
  name,
  BeaconCoordinationPhase.coordinating,
  'phase',
);

BeaconPhasePrimaryAction _actionFromName(String name) => _enumFromName(
  BeaconPhasePrimaryAction.values,
  name,
  BeaconPhasePrimaryAction.none,
  'suggestedAction',
);

BeaconPhaseSlot2Kind _slot2FromName(String name) => _enumFromName(
  BeaconPhaseSlot2Kind.values,
  name,
  BeaconPhaseSlot2Kind.none,
  'slot2Kind',
);

BeaconDisplayTier _tierFromName(String name) => _enumFromName(
  BeaconDisplayTier.values,
  name,
  BeaconDisplayTier.public,
  'tier',
);

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
    canCancel: json['canCancel'] as bool? ?? false,
    canDelete: json['canDelete'] as bool? ?? false,
    everAcknowledgedCommitterCount:
        json['everAcknowledgedCommitterCount'] as int? ?? 0,
  );
}

DateTime? _parseOpt(String? raw) =>
    raw == null || raw.isEmpty ? null : DateTime.tryParse(raw)?.toUtc();
