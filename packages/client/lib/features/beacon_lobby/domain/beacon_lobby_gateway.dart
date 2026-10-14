import 'entity/beacon_lobby.dart';

/// U088 — what the lobby screen needs from the server.
abstract class BeaconLobbyGateway {
  /// Opens the lobby (the server creates it on first use). Throws when the
  /// viewer may not use it: not the author, no live help offer, or banned.
  Future<BeaconLobbyInfo> open(String beaconId);

  /// Messages oldest first.
  Future<List<BeaconLobbyMessage>> messages({
    required String beaconId,
    required String lobbyId,
  });

  Future<void> post({
    required String beaconId,
    required String lobbyId,
    required String body,
  });

  Future<void> ban({required String beaconId, required String userId});

  Future<void> unban({required String beaconId, required String userId});
}
