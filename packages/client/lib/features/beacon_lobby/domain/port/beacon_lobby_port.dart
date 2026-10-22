import '../entity/beacon_lobby.dart';

/// Request Questions (internally the lobby, U088): what it needs from the
/// server.
abstract interface class BeaconLobbyPort {
  /// The viewer's own standing; never throws for "no access".
  Future<BeaconLobbyAccess> access(String beaconId);

  /// Opens Questions (the server creates the scope on first use). Throws
  /// `BeaconLobbyUnavailableException` when the viewer is not in its
  /// audience, was removed by the author, or is blocked.
  Future<BeaconLobbyInfo> open(String beaconId);

  /// One page of messages, oldest first: the newest page, or the page
  /// before [before].
  Future<List<BeaconLobbyMessage>> messages({
    required String beaconId,
    required String lobbyId,
    DateTime? before,
  });

  Future<void> post({
    required String beaconId,
    required String lobbyId,
    required String body,
  });

  /// Marks Questions read (settles its attention items).
  Future<void> markSeen({required String beaconId, required String lobbyId});

  Future<void> ban({required String beaconId, required String userId});

  Future<void> unban({required String beaconId, required String userId});
}
