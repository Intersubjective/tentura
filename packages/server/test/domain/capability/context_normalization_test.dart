import 'package:test/test.dart';

import 'package:tentura_server/domain/capability/context_normalization.dart';

void main() {
  group('capNormalizeContext', () {
    test('null becomes empty string', () {
      expect(capNormalizeContext(null), '');
    });

    test('empty string stays empty', () {
      expect(capNormalizeContext(''), '');
    });

    test('whitespace-only becomes empty', () {
      expect(capNormalizeContext('  '), '');
    });

    test('two characters becomes empty', () {
      expect(capNormalizeContext('ab'), '');
    });

    test('trims and preserves case for valid input', () {
      expect(capNormalizeContext(' AbC '), 'AbC');
    });

    test('32 characters is accepted', () {
      final value = 'a' * 32;
      expect(capNormalizeContext(value), value);
    });

    test('33 characters becomes empty', () {
      expect(capNormalizeContext('a' * 33), '');
    });
  });
}
