import 'package:tentura/domain/exception/generic_exception.dart';

import '../../domain/exception/beacon_lobby_exception.dart';

/// Throws [BeaconLobbyUnavailableException] for its GraphQL error [code]
/// (server 1347, `beaconLobbyAccessDenied`); returns normally for any other
/// code, so the caller falls through to its generic mapping.
void throwIfBeaconLobbyError(int? code) {
  if (code == BeaconLobbyUnavailableException.codeNumber) {
    throw const BeaconLobbyUnavailableException();
  }
}

/// Server `AuthExceptionCode.authUnauthorizedException`: the room API's
/// generic "no access" answer.
const kBeaconLobbyRoomAccessDeniedCode = '1102';

/// A Questions-scope read or write that the room API refuses comes back
/// with its generic access code (1102, "Room or item thread access
/// required"). On a Questions call that can only mean Questions is closed to
/// the viewer — e.g. the author removed them while the screen was open —
/// so it becomes [BeaconLobbyUnavailableException] (#683). Any other error
/// is returned unchanged.
Object beaconLobbyScopeError(Object error) =>
    error is RemoteApiException &&
        error.code?.trim() == kBeaconLobbyRoomAccessDeniedCode
    ? const BeaconLobbyUnavailableException()
    : error;
