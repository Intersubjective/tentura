import '../../domain/exception.dart';

/// Throws the matching [ConstellationException] for a recognized anchor GraphQL
/// error [code]. Returns normally for any other code so the caller can fall
/// through to generic mapping.
void throwIfConstellationError(int? code, Map<String, dynamic>? extensions) {
  switch (code) {
    case ConstellationInvalidTargetException.codeNumber:
      throw const ConstellationInvalidTargetException();
    case ConstellationInvalidCoordinatesException.codeNumber:
      throw const ConstellationInvalidCoordinatesException();
    case ConstellationUnsupportedCoordinateSpaceException.codeNumber:
      throw const ConstellationUnsupportedCoordinateSpaceException();
    case ConstellationTargetUnavailableException.codeNumber:
      throw const ConstellationTargetUnavailableException();
  }
}
