/// Relationship-scoped beacon read gates for V2 use cases (ADR 0008).
abstract class BeaconAccessGuard {
  Future<bool> canReadContent({
    required String beaconId,
    required String viewerId,
  });

  Future<bool> canReadInvolvement({
    required String beaconId,
    required String viewerId,
  });

  Future<bool> canReadTombstone({
    required String beaconId,
    required String viewerId,
  });
}
