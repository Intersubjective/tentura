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
/// required"), never as text to show (#683):
///  - a refused read means Questions is closed to the viewer (the author
///    removed them while the screen was open): [BeaconLobbyUnavailableException];
///  - a refused write only means they may no longer write — they may still
///    read (an offer declined or withdrawn meanwhile), so it becomes
///    [BeaconLobbyPostDeniedException] and the screen re-reads its access.
/// Any other error is returned unchanged.
Object beaconLobbyScopeError(Object error, {bool write = false}) {
  if (error is! RemoteApiException ||
      error.code?.trim() != kBeaconLobbyRoomAccessDeniedCode) {
    return error;
  }
  return write
      ? const BeaconLobbyPostDeniedException()
      : const BeaconLobbyUnavailableException();
}
