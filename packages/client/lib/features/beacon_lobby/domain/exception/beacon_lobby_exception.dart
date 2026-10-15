/// U088 — the server said this viewer may not use the Request lobby (not the
/// author, no live help offer, or removed by the author). Any other failure
/// is a failed request, not a denial.
final class BeaconLobbyUnavailableException implements Exception {
  const BeaconLobbyUnavailableException();

  /// Server `BeaconExceptionCode.beaconLobbyAccessDenied`.
  static const codeNumber = 1346;
}
