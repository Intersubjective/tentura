abstract class BeaconRoomCoParticipantLookupPort {
  /// Peers in [peerIds] that share at least one admitted beacon room with
  /// [viewerId].
  Future<Set<String>> coParticipantPeerIds({
    required String viewerId,
    required Iterable<String> peerIds,
  });
}
