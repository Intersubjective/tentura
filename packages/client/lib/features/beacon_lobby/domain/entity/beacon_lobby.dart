/// U088 — the Request lobby, as the viewer sees it.
class BeaconLobbyInfo {
  const BeaconLobbyInfo({
    required this.beaconId,
    required this.lobbyId,
    required this.isAuthor,
    required this.canPost,
    this.bannedUserIds = const [],
  });

  final String beaconId;

  /// Thread scope id of the lobby (server `coordination_item` kind 7).
  final String lobbyId;

  final bool isAuthor;
  final bool canPost;

  /// Only filled for the author.
  final List<String> bannedUserIds;
}

class BeaconLobbyMessage {
  const BeaconLobbyMessage({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.body,
    this.createdAt,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String body;
  final DateTime? createdAt;
}
