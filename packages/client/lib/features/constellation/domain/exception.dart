/// Typed constellation anchor failures mapped from GraphQL `extensions.code`.
sealed class ConstellationException implements Exception {
  const ConstellationException([this.message]);

  final String? message;

  @override
  String toString() => message ?? super.toString();
}

/// Invalid target kind, empty id, or ego person pin attempt.
final class ConstellationInvalidTargetException extends ConstellationException {
  const ConstellationInvalidTargetException([
    super.message = 'Invalid constellation anchor target',
  ]);

  static const codeNumber = 1700;
}

/// Non-finite or out-of-range v1 coordinates.
final class ConstellationInvalidCoordinatesException
    extends ConstellationException {
  const ConstellationInvalidCoordinatesException([
    super.message = 'Invalid constellation anchor coordinates',
  ]);

  static const codeNumber = 1701;
}

/// Unsupported [ConstellationAnchorPosition.coordinateSpaceVersion].
final class ConstellationUnsupportedCoordinateSpaceException
    extends ConstellationException {
  const ConstellationUnsupportedCoordinateSpaceException([
    super.message = 'Unsupported coordinate space',
  ]);

  static const codeNumber = 1702;
}

/// Missing, forbidden, or otherwise unavailable anchor target.
final class ConstellationTargetUnavailableException
    extends ConstellationException {
  const ConstellationTargetUnavailableException([
    super.message = 'Constellation anchor target unavailable',
  ]);

  static const codeNumber = 1703;
}
