/// Relationship-scoped beacon read gates for V2 use cases (ADR 0008).
abstract class BeaconAccessGuard {
  Future<bool> canReadContent({
    required String beaconId,
    required String viewerId,
  });

  /// Those of [beaconIds] whose content [viewerId] may read
  /// ([canReadContent]), checked in one query.
  Future<Set<String>> readableContentIds({
    required Iterable<String> beaconIds,
    required String viewerId,
  });

  /// Those of [viewerIds] who may read the content of [beaconId]
  /// ([canReadContent]), checked in one query.
  Future<Set<String>> readableContentViewerIds({
    required String beaconId,
    required Iterable<String> viewerIds,
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
