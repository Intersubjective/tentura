abstract class PersonVisibilityRepositoryPort {
  /// Peers in [peerIds] that are mutually visible to [viewerId] in [context],
  /// using the canonical `person_visibility_peers` SQL projection.
  ///
  /// Incoming-only MeritRank is not a visibility signal (m0151): first for
  /// speed, second for simplicity. Mixed `trustIn + mrOut` is unchanged.
  Future<Set<String>> mutuallyVisiblePeerIds({
    required String viewerId,
    required Iterable<String> peerIds,
    required String context,
  });
}
