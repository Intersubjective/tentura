import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/util/ellipsize.dart';

void main() {
  group('ellipsize', () {
    test('truncates with ellipsis when string exceeds maxLength', () {
      expect(ellipsize('hello world', 8), 'hello w…');
    });

    test('returns string unchanged when within maxLength', () {
      expect(ellipsize('hi', 8), 'hi');
    });

    test('returns string unchanged when length equals maxLength', () {
      expect(ellipsize('abc', 3), 'abc');
    });

    test('returns empty string when maxLength is less than 1', () {
      expect(ellipsize('hello world', 0), '');
      expect(ellipsize('hello world', -1), '');
    });
  });
}
