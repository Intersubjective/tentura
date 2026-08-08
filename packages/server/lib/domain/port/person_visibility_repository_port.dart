abstract class PersonVisibilityRepositoryPort {
  /// Peers in [peerIds] that are mutually visible to [viewerId] in [context],
  /// using the canonical `person_visibility_peers` SQL projection.
  Future<Set<String>> mutuallyVisiblePeerIds({
    required String viewerId,
    required Iterable<String> peerIds,
    required String context,
  });
}
