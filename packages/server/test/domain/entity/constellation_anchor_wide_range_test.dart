import 'package:test/test.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_root/domain/constellation/constellation_geometry.dart';

/// The widened Field placement bound, shared by the client, the server
/// validation and the database CHECK.
const _bound = kConstellationCoordinateMaxUnits;

void main() {
  group('Anchor axis range check accepts the widened placement range', () {
    test('the shared bound is symmetric and wider than the old ±10', () {
      expect(_bound, greaterThan(10));
      expect(kConstellationCoordinateMinUnits, -_bound);
    });

    for (final (value, expected) in [
      (0.0, true),
      (10.0, true),
      (-10.0, true),
      (11.0, true),
      (-11.0, true),
      (_bound, true),
      (-_bound, true),
      (_bound + 0.001, false),
      (-(_bound + 0.001), false),
      (double.nan, false),
      (double.infinity, false),
      (double.negativeInfinity, false),
    ]) {
      test('isFiniteV1Axis($value) is $expected', () {
        expect(ConstellationAnchorPosition.isFiniteV1Axis(value), expected);
      });
    }

    test('a position at (11, -11) validates', () {
      final result = ConstellationAnchorPosition.validate(
        xUnits: 11,
        yUnits: -11,
        coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
      );
      expect(result, isA<ConstellationAnchorPositionValid>());
      final position = (result as ConstellationAnchorPositionValid).position;
      expect(position.xUnits, 11);
      expect(position.yUnits, -11);
    });

    test('a position past the bound is out of range', () {
      final result = ConstellationAnchorPosition.validate(
        xUnits: _bound + 1,
        yUnits: 0,
        coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
      );
      expect(
        (result as ConstellationAnchorPositionInvalid).reason,
        ConstellationAnchorPositionInvalidReason.outOfRange,
      );
    });
  });
}
