abstract class BeaconRoomCoParticipantLookupPort {
  /// Peers in [peerIds] that share at least one admitted beacon room with
  /// [viewerId].
  Future<Set<String>> coParticipantPeerIds({
    required String viewerId,
    required Iterable<String> peerIds,
  });

  /// Everyone in the room of [beaconId]: the Request's author, its stewards
  /// and its admitted participants.
  Future<Set<String>> roomMemberUserIds({required String beaconId});
}
