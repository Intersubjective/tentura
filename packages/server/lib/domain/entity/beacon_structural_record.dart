import 'package:tentura_root/domain/entity/beacon_status.dart';

/// Minimal structural facts for a deleted or owner-erased request tombstone.
///
/// Used when [BeaconEntity] cannot be loaded because the owner row is gone
/// but the beacon identity and hierarchy links must survive (§4.5 point 6).
final class BeaconStructuralRecord {
  const BeaconStructuralRecord({
    required this.beaconId,
    required this.status,
    required this.isTombstone,
    this.parentBeaconId,
    this.publishedAt,
  });

  final String beaconId;
  final BeaconStatus status;
  final bool isTombstone;
  final String? parentBeaconId;
  final DateTime? publishedAt;
}
