import 'package:test/test.dart';

import 'package:tentura_server/domain/util/oidc_claim_util.dart';

void main() {
  group('parseOidcEmailVerified', () {
    test('true boolean is authoritative', () {
      expect(parseOidcEmailVerified(true), isTrue);
    });

    test('string true is authoritative', () {
      expect(parseOidcEmailVerified('true'), isTrue);
      expect(parseOidcEmailVerified('TRUE'), isTrue);
    });

    test('false and ambiguous values are non-authoritative', () {
      expect(parseOidcEmailVerified(false), isFalse);
      expect(parseOidcEmailVerified('false'), isFalse);
      expect(parseOidcEmailVerified(null), isFalse);
      expect(parseOidcEmailVerified('yes'), isFalse);
      expect(parseOidcEmailVerified(1), isFalse);
    });
  });
}
