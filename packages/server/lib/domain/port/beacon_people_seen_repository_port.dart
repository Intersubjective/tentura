abstract interface class BeaconPeopleSeenRepositoryPort {
  /// Monotonic upsert of the People-tab read watermark; returns the persisted
  /// (greater of stored and [at]) value.
  Future<DateTime> markSeen({
    required String userId,
    required String beaconId,
    required DateTime at,
  });

  /// Watermarks for [userIds] on [beaconId]; users without a row are omitted.
  Future<Map<String, DateTime>> lastSeenByUserIds({
    required String beaconId,
    required List<String> userIds,
  });
}
