import 'package:tentura_root/domain/entity/beacon_access.dart';
import 'package:test/test.dart';

void main() {
  test('reason encode/decode round-trips every 8-bit mask', () {
    for (var mask = 0; mask < 256; mask++) {
      expect(
        BeaconAccessReason.encode(BeaconAccessReason.decode(mask)),
        mask,
        reason: 'mask $mask',
      );
    }
  });

  test('level from reasons: zero and each single bit', () {
    const expected = {
      0: BeaconAccessLevel.stranger,
      1: BeaconAccessLevel.author,
      2: BeaconAccessLevel.member,
      4: BeaconAccessLevel.member,
      8: BeaconAccessLevel.observer,
      16: BeaconAccessLevel.observer,
      32: BeaconAccessLevel.observer,
      64: BeaconAccessLevel.observer,
      128: BeaconAccessLevel.observer,
    };
    for (final MapEntry(:key, :value) in expected.entries) {
      expect(beaconAccessLevelFromReasons(key), value, reason: 'mask $key');
    }
  });
}
