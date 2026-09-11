import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/data/model/constellation_error_mapper.dart';
import 'package:tentura/features/constellation/domain/exception.dart';

void main() {
  group('throwIfConstellationError', () {
    test('translates constellation anchor codes 1700–1703', () {
      expect(
        () => throwIfConstellationError(1700, null),
        throwsA(isA<ConstellationInvalidTargetException>()),
      );
      expect(
        () => throwIfConstellationError(1701, null),
        throwsA(isA<ConstellationInvalidCoordinatesException>()),
      );
      expect(
        () => throwIfConstellationError(1702, null),
        throwsA(isA<ConstellationUnsupportedCoordinateSpaceException>()),
      );
      expect(
        () => throwIfConstellationError(1703, null),
        throwsA(isA<ConstellationTargetUnavailableException>()),
      );
    });

    test('an unrecognized code does not throw', () {
      expect(() => throwIfConstellationError(1704, null), returnsNormally);
      expect(() => throwIfConstellationError(1309, null), returnsNormally);
      expect(() => throwIfConstellationError(null, null), returnsNormally);
    });
  });
}
