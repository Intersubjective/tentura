import '../../domain/exception/beacon_lobby_exception.dart';

/// Throws [BeaconLobbyUnavailableException] for its GraphQL error [code]
/// (server 1347, `beaconLobbyAccessDenied`); returns normally for any other
/// code, so the caller falls through to its generic mapping.
void throwIfBeaconLobbyError(int? code) {
  if (code == BeaconLobbyUnavailableException.codeNumber) {
    throw const BeaconLobbyUnavailableException();
  }
}
