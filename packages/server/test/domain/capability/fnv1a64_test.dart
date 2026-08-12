import 'package:test/test.dart';

import 'package:tentura_server/domain/capability/fnv1a64.dart';

void main() {
  group('fnv1a64', () {
    test('pinned empty string vector', () {
      expect(fnv1a64(''), equals(0xcbf29ce484222325));
    });

    test('pinned single-byte vector', () {
      expect(fnv1a64('a'), equals(0xaf63dc4c8601ec8c));
    });

    test('pinned foobar vector', () {
      expect(fnv1a64('foobar'), equals(0x85944171f73967e8));
    });

    test('longer arbitrary string catches byte-loop off-by-one', () {
      expect(
        fnv1a64('The quick brown fox jumps over the lazy dog'),
        equals(-866459186506731248),
      );
    });
  });

  group('fnv1a64Mod', () {
    test('unsigned semantics against a known negative-signed hash', () {
      // fnv1a64('a') = 0xaf63dc4c8601ec8c, whose sign bit is set, so the
      // Dart int is negative (-5808556873153909620). The TRUE unsigned
      // 64-bit value is 12638187200555641996 (verified independently via
      // BigInt/Python cross-check); a signed-mod implementation silently
      // computes a different, wrong result for every modulus here. Pinning
      // exact expected values, not just "in range", is what actually
      // exercises the unsigned conversion — a range assertion passes
      // whether or not the conversion is correct, since Dart's `%` on a
      // positive modulus is always non-negative regardless.
      expect(fnv1a64('a'), equals(-5808556873153909620));
      expect(fnv1a64Mod('a', 3), equals(1));
      expect(fnv1a64Mod('a', 7), equals(5));
      expect(fnv1a64Mod('a', 10), equals(6));
      expect(fnv1a64Mod('a', 1000003), equals(783675));
    });

    test('deterministic offset for fixed beacon id', () {
      const beaconId = 'B_test_beacon';
      expect(fnv1a64Mod(beaconId, 5), equals(fnv1a64Mod(beaconId, 5)));
    });
  });
}
