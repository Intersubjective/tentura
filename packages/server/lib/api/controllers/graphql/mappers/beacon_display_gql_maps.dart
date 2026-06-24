import 'package:tentura_server/domain/entity/beacon_display_status.dart';
import 'package:tentura_server/domain/entity/gql_public/beacon_status_result.dart';

Map<String, dynamic> beaconStatusResultToGqlMap(BeaconStatusResult dto) => {
  'beaconId': dto.beaconId,
  'status': dto.status,
  'statusChangedAt': dto.statusChangedAt?.toUtc().toIso8601String(),
};

Map<String, dynamic> beaconDisplayStatusToGqlMap(BeaconDisplayStatus dto) => {
  'beaconId': dto.beaconId,
  'status': dto.status.smallintValue,
  'phase': dto.phase.name,
  'suggestedAction': dto.suggestedAction.name,
  'slot2Kind': dto.slot2Kind.name,
  'tier': dto.tier.name,
  'reviewClosesAt': dto.reviewClosesAt?.toUtc().toIso8601String(),
  'lastActivityAt': dto.lastActivityAt?.toUtc().toIso8601String(),
  'lifecycleEndedAt': dto.lifecycleEndedAt?.toUtc().toIso8601String(),
};

/// Legacy alias for mutation map name.
Map<String, dynamic> coordinationStatusResultToGqlMap(
  BeaconStatusResult dto,
) => beaconStatusResultToGqlMap(dto);
