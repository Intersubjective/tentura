import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/exception.dart';

/// Shared visibility gate for fork and lineage-suggestion reads.
Future<void> assertBeaconLineageSourceVisible({
  required BeaconAccessGuard guard,
  required String beaconId,
  required String userId,
}) async {
  if (!await guard.canReadContent(beaconId: beaconId, viewerId: userId)) {
    throw const BeaconCreateException(
      description: 'Request is not available as a lineage source',
    );
  }
}
