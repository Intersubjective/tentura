abstract class VoteUserFriendshipLookupPort {
  /// Peers in [peerIds] with reciprocal positive `vote_user` edges.
  Future<Set<String>> reciprocalPositivePeerIds({
    required String viewerId,
    required Iterable<String> peerIds,
  });

  Future<bool> isReciprocalSubscribe({
    required String viewerId,
    required String peerId,
  });

  /// One-way positive trust edge (mutual subscribe is a strict subset).
  Future<bool> isSubscribedTo({
    required String viewerId,
    required String peerId,
  });
}
