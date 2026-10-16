/// U088 — the Request lobby: its scope item and who is banned from it.
abstract class BeaconLobbyRepositoryPort {
  /// The lobby item id of [beaconId], creating it on first use.
  Future<String> ensureLobby({
    required String beaconId,
    required String authorId,
  });

  /// The Request a lobby item belongs to, or null when [itemId] is not a
  /// lobby.
  Future<String?> lobbyBeaconId(String itemId);

  /// Whether [userId] has a live (not withdrawn) help offer on [beaconId].
  Future<bool> hasActiveHelpOffer({
    required String beaconId,
    required String userId,
  });

  Future<bool> isBanned({required String beaconId, required String userId});

  Future<void> ban({
    required String beaconId,
    required String userId,
    required String bannedBy,
  });

  Future<void> unban({required String beaconId, required String userId});

  /// Banned user ids of [beaconId], oldest ban first.
  Future<List<String>> bannedUserIds(String beaconId);
}
