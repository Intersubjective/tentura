// #607: Coordinates.isNotEmpty used `&&`, so a real point with one
// coordinate exactly 0 (on the equator or the prime meridian) was reported
// as empty. Only the unset 0,0 value is empty.
import 'package:tentura_root/domain/entity/coordinates.dart';
import 'package:test/test.dart';

void main() {
  test('0,0 is the unset value', () {
    expect(Coordinates.zero.isEmpty, isTrue);
    expect(Coordinates.zero.isNotEmpty, isFalse);
  });

  test('a point on the equator is not empty', () {
    const point = Coordinates(lat: 0, long: 32.58);
    expect(point.isEmpty, isFalse);
    expect(point.isNotEmpty, isTrue);
  });

  test('a point on the prime meridian is not empty', () {
    const point = Coordinates(lat: 51.48, long: 0);
    expect(point.isEmpty, isFalse);
    expect(point.isNotEmpty, isTrue);
  });

  test('an ordinary point is not empty', () {
    const point = Coordinates(lat: -33.86, long: 151.21);
    expect(point.isEmpty, isFalse);
    expect(point.isNotEmpty, isTrue);
  });

  test('isNotEmpty is always the opposite of isEmpty', () {
    for (final (lat, long) in [
      (0.0, 0.0),
      (0.0, 1.0),
      (1.0, 0.0),
      (1.0, 1.0),
    ]) {
      final point = Coordinates(lat: lat, long: long);
      expect(point.isNotEmpty != point.isEmpty, isTrue, reason: '$point');
    }
  });
}
