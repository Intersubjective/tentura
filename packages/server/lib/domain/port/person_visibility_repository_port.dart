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

  /// Peers sharing an active request (open / reviewOpen / needsMoreHelp /
  /// enoughHelp) with [viewerId], minus blocks (`person_bond_peers`).
  Future<Set<String>> bondPeerIds({required String viewerId});

  /// Peers in [peerIds] that are mutually visible (trust) OR bonded to
  /// [viewerId]. Used for forwarding only; the bond never feeds discovery (D4).
  Future<Set<String>> personVisiblePeerIds({
    required String viewerId,
    required Iterable<String> peerIds,
    required String context,
  });

  /// Active requests shared by [viewerId] and [peerId] (at most 20).
  Future<List<({String beaconId, String title})>> sharedContexts({
    required String viewerId,
    required String peerId,
  });
}
