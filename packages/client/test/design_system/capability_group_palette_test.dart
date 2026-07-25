import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_capability_colors.dart';
import 'package:tentura/domain/capability/capability_group.dart';

/// WCAG relative luminance for an opaque sRGB colour.
double relativeLuminance(Color color) {
  double channel(double c) {
    final v = c;
    return v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  final r = channel(color.r);
  final g = channel(color.g);
  final b = channel(color.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

double contrastRatio(Color a, Color b) {
  final l1 = relativeLuminance(a);
  final l2 = relativeLuminance(b);
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('TenturaCapabilityColors palette constants', () {
    test('light swatches match plan hex values', () {
      expect(TenturaCapabilityColors.light.logistics.container, const Color(0xFFEEF2FF));
      expect(TenturaCapabilityColors.light.logistics.onContainer, const Color(0xFF3730A3));
      expect(TenturaCapabilityColors.light.communication.container, const Color(0xFFECFEFF));
      expect(TenturaCapabilityColors.light.communication.onContainer, const Color(0xFF155E75));
      expect(TenturaCapabilityColors.light.knowledge.container, const Color(0xFFF5F3FF));
      expect(TenturaCapabilityColors.light.knowledge.onContainer, const Color(0xFF5B21B6));
      expect(TenturaCapabilityColors.light.care.container, const Color(0xFFFDF4FF));
      expect(TenturaCapabilityColors.light.care.onContainer, const Color(0xFF86198F));
      expect(TenturaCapabilityColors.light.resources.container, const Color(0xFFF0FDFA));
      expect(TenturaCapabilityColors.light.resources.onContainer, const Color(0xFF115E59));
      expect(TenturaCapabilityColors.light.technical.container, const Color(0xFFF5F5F4));
      expect(TenturaCapabilityColors.light.technical.onContainer, const Color(0xFF44403C));
      expect(TenturaCapabilityColors.light.special.container, const Color(0xFFF1F5F9));
      expect(TenturaCapabilityColors.light.special.onContainer, const Color(0xFF475569));
    });

    test('dark swatches match plan hex values', () {
      expect(TenturaCapabilityColors.dark.logistics.container, const Color(0xFF252F4A));
      expect(TenturaCapabilityColors.dark.logistics.onContainer, const Color(0xFFA5B4FC));
      expect(TenturaCapabilityColors.dark.communication.container, const Color(0xFF16323C));
      expect(TenturaCapabilityColors.dark.communication.onContainer, const Color(0xFF67E8F9));
      expect(TenturaCapabilityColors.dark.knowledge.container, const Color(0xFF2A2647));
      expect(TenturaCapabilityColors.dark.knowledge.onContainer, const Color(0xFFC4B5FD));
      expect(TenturaCapabilityColors.dark.care.container, const Color(0xFF3A1F3F));
      expect(TenturaCapabilityColors.dark.care.onContainer, const Color(0xFFF0ABFC));
      expect(TenturaCapabilityColors.dark.resources.container, const Color(0xFF123832));
      expect(TenturaCapabilityColors.dark.resources.onContainer, const Color(0xFF5EEAD4));
      expect(TenturaCapabilityColors.dark.technical.container, const Color(0xFF292524));
      expect(TenturaCapabilityColors.dark.technical.onContainer, const Color(0xFFD6D3D1));
      expect(TenturaCapabilityColors.dark.special.container, const Color(0xFF273240));
      expect(TenturaCapabilityColors.dark.special.onContainer, const Color(0xFFCBD5E1));
    });

    test('every pair clears WCAG AA; only three pairs are below AAA', () {
      final aaPairs = <(String, CapabilitySwatch)>[
        ('dark logistics', TenturaCapabilityColors.dark.logistics),
        ('light communication', TenturaCapabilityColors.light.communication),
        ('light special', TenturaCapabilityColors.light.special),
      ];

      for (final entry in aaPairs) {
        final ratio = contrastRatio(entry.$2.onContainer, entry.$2.container);
        expect(ratio, greaterThanOrEqualTo(4.5), reason: '${entry.$1} AA');
        expect(ratio, lessThan(7.0), reason: '${entry.$1} must not be called AAA');
      }

      // Fixture tolerances from recalculation (plan §5.3 wording).
      expect(
        contrastRatio(
          TenturaCapabilityColors.dark.logistics.onContainer,
          TenturaCapabilityColors.dark.logistics.container,
        ),
        closeTo(6.65, 0.05),
      );
      expect(
        contrastRatio(
          TenturaCapabilityColors.light.communication.onContainer,
          TenturaCapabilityColors.light.communication.container,
        ),
        closeTo(6.99, 0.05),
      );
      expect(
        contrastRatio(
          TenturaCapabilityColors.light.special.onContainer,
          TenturaCapabilityColors.light.special.container,
        ),
        closeTo(6.92, 0.05),
      );

      final aaaCandidates = <(String, CapabilitySwatch)>[
        for (final group in CapabilityGroup.values)
          (
            'light ${group.name}',
            TenturaCapabilityColors.light.swatchFor(group),
          ),
        for (final group in CapabilityGroup.values)
          (
            'dark ${group.name}',
            TenturaCapabilityColors.dark.swatchFor(group),
          ),
      ].where(
        (entry) => !aaPairs.any((aa) => identical(aa.$2, entry.$2)),
      );

      for (final entry in aaaCandidates) {
        final ratio = contrastRatio(entry.$2.onContainer, entry.$2.container);
        expect(ratio, greaterThanOrEqualTo(7.0), reason: '${entry.$1} AAA');
      }
    });
  });
}
