/// One person on an ordered explicit-trust path.
typedef ConstellationTrustChainPerson = ({String userId, String displayName});

// ignore: one_member_abstracts -- narrow read boundary
abstract interface class ConstellationTrustChainPort {
  /// The shortest directed positive-trust path, viewer first, at most four
  /// hops. Intermediates must be visible; the target must have Field presence.
  /// Blocks either way with the viewer or between neighbours exclude a path.
  /// Equal-length paths are ordered lexicographically by user id.
  Future<List<ConstellationTrustChainPerson>> trustChain({
    required String viewerId,
    required String context,
    required String personId,
  });
}
