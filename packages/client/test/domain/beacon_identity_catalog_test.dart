import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_identity_catalog.dart';

void main() {
  group('paletteSwatchForArgb', () {
    test('returns swatch for known palette ARGB', () {
      final first = kBeaconIdentityPalette.first;
      expect(
        paletteSwatchForArgb(first.backgroundArgb),
        first,
      );
    });

    test('returns null for null', () {
      expect(paletteSwatchForArgb(null), isNull);
    });

    test('returns null for unknown ARGB', () {
      expect(paletteSwatchForArgb(0xFFEEDDCC), isNull);
    });
  });

  group('BeaconPaletteSwatch', () {
    test('equality by ARGB pair', () {
      const a = BeaconPaletteSwatch(
        backgroundArgb: 0xFF112233,
        foregroundArgb: 0xFFEEDDCC,
      );
      const b = BeaconPaletteSwatch(
        backgroundArgb: 0xFF112233,
        foregroundArgb: 0xFFEEDDCC,
      );
      const c = BeaconPaletteSwatch(
        backgroundArgb: 0xFF112234,
        foregroundArgb: 0xFFEEDDCC,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });
  });

  group('kBeaconIdentityIcons', () {
    test('curated size in expected range', () {
      expect(kBeaconIdentityIcons.length, inInclusiveRange(100, 130));
    });

    test('every icon has a non-empty ontology label', () {
      for (final e in kBeaconIdentityIcons.entries) {
        expect(e.value.label, isNotEmpty, reason: 'key ${e.key}');
      }
    });
  });
}
