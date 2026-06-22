import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/app/platform/orientation_policy_native.dart';

void main() {
  group('shouldLockPortraitForLogicalShortestSide', () {
    test('locks when below compact threshold', () {
      expect(shouldLockPortraitForLogicalShortestSide(599), isTrue);
      expect(shouldLockPortraitForLogicalShortestSide(390), isTrue);
    });

    test('unlocks at tablet width', () {
      expect(shouldLockPortraitForLogicalShortestSide(600), isFalse);
      expect(shouldLockPortraitForLogicalShortestSide(768), isFalse);
    });
  });
}
