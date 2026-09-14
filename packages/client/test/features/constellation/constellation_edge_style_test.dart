import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_edge_style.dart';

Color compositeOverBackground(Color foreground, Color background) {
  if (foreground.a >= 1) {
    return foreground;
  }
  return Color.alphaBlend(foreground, background);
}

double contrastRatio(Color foreground, Color background) {
  final fg = compositeOverBackground(foreground, background);
  final l1 = fg.computeLuminance();
  final l2 = background.computeLuminance();
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  for (final theme in [TenturaTheme.light(), TenturaTheme.dark()]) {
    test('edge colors meet contrast on bg (${theme.brightness.name})', () {
      final tt = theme.extension<TenturaTokens>()!;
      final scheme = theme.colorScheme;
      for (final kind in ConstellationEdgeKind.values) {
        final style = constellationEdgeStyle(kind, tt, scheme);
        final ratio = contrastRatio(style.color, tt.bg);
        expect(
          ratio,
          greaterThanOrEqualTo(3.0),
          reason: '$kind on ${theme.brightness.name}',
        );
      }
    });
  }

  test('path kinds differ by dash pattern', () {
    final tt = TenturaTheme.light().extension<TenturaTokens>()!;
    final scheme = TenturaTheme.light().colorScheme;
    final tier1 = constellationEdgeStyle(ConstellationEdgeKind.tier1Path, tt, scheme);
    final tier2 = constellationEdgeStyle(ConstellationEdgeKind.tier2Path, tt, scheme);
    final stub = constellationEdgeStyle(ConstellationEdgeKind.ringStub, tt, scheme);

    expect(tier1.dash, isNot(equals(tier2.dash)));
    expect((stub.dash, stub.gap), isNot((tier1.dash, tier1.gap)));
    expect((stub.dash, stub.gap), isNot((tier2.dash, tier2.gap)));
  });
}
