import '../entity/beacon_lobby.dart';

/// Request Questions (internally the lobby, U088): what it needs from the
/// server. Its messages go through the room API like any thread's (#726).
abstract interface class BeaconLobbyPort {
  /// The viewer's own standing; never throws for "no access".
  Future<BeaconLobbyAccess> access(String beaconId);

  /// Opens Questions (the server creates the scope on first use). Throws
  /// `BeaconLobbyUnavailableException` when the viewer is not in its
  /// audience, was removed by the author, or is blocked.
  Future<BeaconLobbyInfo> open(String beaconId);

  Future<void> ban({required String beaconId, required String userId});

  Future<void> unban({required String beaconId, required String userId});
}
