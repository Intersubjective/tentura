/// U088 — the server said this viewer may not use the Request lobby (not the
/// author, no live help offer, or removed by the author). Any other failure
/// is a failed request, not a denial.
final class BeaconLobbyUnavailableException implements Exception {
  const BeaconLobbyUnavailableException();

  /// Server `BeaconExceptionCode.beaconLobbyAccessDenied`.
  static const codeNumber = 1347;
}

/// #683 — the server refused a Questions post: the viewer may no longer
/// write (removed, or their offer was declined or withdrawn meanwhile). What
/// they may still do is for a fresh read of their access to say.
final class BeaconLobbyPostDeniedException implements Exception {
  const BeaconLobbyPostDeniedException();
}
