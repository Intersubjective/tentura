import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

/// WCAG relative luminance for an opaque sRGB colour.
double _relativeLuminance(Color color) {
  double channel(double c) =>
      c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

double _contrastRatio(Color a, Color b) {
  final l1 = _relativeLuminance(a);
  final l2 = _relativeLuminance(b);
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

void main() {
  group('TenturaTagColors palette', () {
    for (final entry in <(String, TenturaTagColors)>[
      ('light', TenturaTagColors.light),
      ('dark', TenturaTagColors.dark),
    ]) {
      final name = entry.$1;
      final colors = entry.$2;

      test('$name palette has eight swatches', () {
        expect(colors.swatches, hasLength(8));
      });

      test('$name swatches are visually distinct from each other', () {
        final containers = colors.swatches.map((s) => s.container).toSet();
        final accents = colors.swatches.map((s) => s.accent).toSet();
        expect(containers, hasLength(8));
        expect(accents, hasLength(8));
      });

      test('$name accent differs from its container', () {
        for (final (i, swatch) in colors.swatches.indexed) {
          expect(swatch.accent, isNot(swatch.container), reason: 'swatch $i');
        }
      });

      // Same floor as the capability palette: every text pair clears AA.
      test('$name on-container text clears WCAG AA on its container', () {
        for (final (i, swatch) in colors.swatches.indexed) {
          expect(
            _contrastRatio(swatch.onContainer, swatch.container),
            greaterThanOrEqualTo(4.5),
            reason: '$name swatch $i',
          );
        }
      });

      test(
        '$name accent stays visible against its container (non-text 3:1)',
        () {
          for (final (i, swatch) in colors.swatches.indexed) {
            expect(
              _contrastRatio(swatch.accent, swatch.container),
              greaterThanOrEqualTo(3.0),
              reason: '$name swatch $i',
            );
          }
        },
      );

      test('$name swatchFor maps every colour index 0-7 to that swatch', () {
        for (var i = 0; i < 8; i++) {
          expect(colors.swatchFor(i), colors.swatches[i]);
        }
      });
    }

    test(
      'swatchFor wraps an out-of-range colour index instead of throwing',
      () {
        const colors = TenturaTagColors.light;
        expect(colors.swatchFor(8), colors.swatchFor(0));
        expect(colors.swatchFor(11), colors.swatchFor(3));
      },
    );

    test('lerp at the ends returns the endpoints', () {
      const light = TenturaTagColors.light;
      const dark = TenturaTagColors.dark;
      expect(light.lerp(dark, 0).swatches, light.swatches);
      expect(light.lerp(dark, 1).swatches, dark.swatches);
    });
  });

  group('TenturaTagColors theme registration', () {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets('$brightness theme exposes the matching palette', (
        tester,
      ) async {
        late TenturaTagColors colors;
        await tester.pumpWidget(
          MaterialApp(
            theme: brightness == Brightness.light
                ? TenturaTheme.light()
                : TenturaTheme.dark(),
            home: TenturaResponsiveScope(
              child: Builder(
                builder: (context) {
                  colors = context.tagColors;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );

        final expected = brightness == Brightness.light
            ? TenturaTagColors.light
            : TenturaTagColors.dark;
        expect(colors.swatches, expected.swatches);
      });
    }

    testWidgets('tagColors fails fast when the extension is absent', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Builder(
            builder: (context) {
              expect(() => context.tagColors, throwsA(anything));
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });
  });
}
