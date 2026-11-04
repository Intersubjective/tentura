/// Owns first-seen records and the viewer's acknowledgement of those people.
abstract interface class ConstellationNewPeopleRepositoryPort {
  /// Records missing people once; the viewer's initial population is backfilled.
  Future<void> recordFirstSeen({
    required String viewerId,
    required List<String> peerIds,
    required bool backfill,
  });

  /// A repeat preserves the original acknowledgement and first-seen times.
  /// Unknown peers and rows belonging only to another viewer are no-ops.
  Future<void> acknowledge({
    required String viewerId,
    required List<String> peerIds,
  });
}
