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
    test('unsigned semantics when sign bit is set', () {
      const hashWithSignBit = 0x8000000000000001;
      expect(hashWithSignBit.isNegative, isTrue);
      expect(fnv1a64Mod('sign-bit-probe', 7), inInclusiveRange(0, 6));
    });

    test('deterministic offset for fixed beacon id', () {
      const beaconId = 'B_test_beacon';
      expect(fnv1a64Mod(beaconId, 5), equals(fnv1a64Mod(beaconId, 5)));
    });
  });
}
