import 'package:meta/meta.dart';

/// Result of `setCoordinationResponse` (GraphQL `CoordinationStatusResult`).
@immutable
class CoordinationStatusResult {
  const CoordinationStatusResult({
    required this.beaconId,
    required this.coordinationStatus,
    this.coordinationStatusUpdatedAt,
  });

  final String beaconId;
  final int coordinationStatus;
  final DateTime? coordinationStatusUpdatedAt;
}
