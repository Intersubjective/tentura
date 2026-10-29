import 'package:tentura_server/domain/entity/questions_access.dart';

/// Request Questions (internally: the Request lobby, U088): its scope item,
/// who is banned from it, and the one access policy (m0254).
abstract class BeaconLobbyRepositoryPort {
  /// The Questions item id of [beaconId], creating it on first use.
  Future<String> ensureLobby({
    required String beaconId,
    required String authorId,
  });

  /// The Questions item id of [beaconId], or null before its first open.
  Future<String?> findLobby(String beaconId);

  /// The Request a Questions item belongs to, or null when [itemId] is not a
  /// Questions item.
  Future<String?> lobbyBeaconId(String itemId);

  /// The policy for each of [userIds] on [beaconId], in one query. Ids the
  /// policy does not return (e.g. a Post, an unknown beacon) are
  /// [QuestionsAccess.none].
  Future<Map<String, QuestionsAccess>> accessLevels({
    required String beaconId,
    required Iterable<String> userIds,
  });

  /// What [userId]'s own standing on [beaconId] looks like, to name the
  /// reason behind a read-only or no-access level (#657). Never grants
  /// access.
  Future<QuestionsStandingFacts> standingFacts({
    required String beaconId,
    required String userId,
  });

  /// Everyone who may read [beaconId]'s Questions, with names for mentions.
  Future<List<QuestionsAudienceMember>> audience(String beaconId);

  /// Messages of [lobbyId] that [viewerId] would see (authors with a block
  /// either way are hidden), including unread after the viewer's Questions cursor.
  Future<({int messageCount, int unreadCount})> countVisibleMessages({
    required String lobbyId,
    required String viewerId,
  });

  /// Bans [userId]. Returns false when there is no such user.
  Future<bool> ban({
    required String beaconId,
    required String userId,
    required String bannedBy,
  });

  Future<void> unban({required String beaconId, required String userId});

  /// Banned people of [beaconId], oldest ban first.
  Future<List<QuestionsBannedUser>> bannedUsers(String beaconId);
}
