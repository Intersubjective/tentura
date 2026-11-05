import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  group('TenturaFieldBackdropColors (#1022)', () {
    for (final (name, theme) in [
      ('light', TenturaTheme.light()),
      ('dark', TenturaTheme.dark()),
    ]) {
      test('$name: contour line sits at ~1.1-1.2:1 on the Field surface', () {
        final backdrop = theme.extension<TenturaFieldBackdropColors>();
        expect(backdrop, isNotNull);
        // The Field paints on the scaffold surface.
        final surface = theme.scaffoldBackgroundColor;
        expect(surface, theme.colorScheme.surface);
        final ratio = _contrast(backdrop!.line, surface);
        expect(ratio, inInclusiveRange(1.05, 1.25), reason: 'ratio $ratio');
        expect(backdrop.line.a, 1.0, reason: 'opaque, no raw alpha');
      });

      test('$name: derived from the surface roles, never a tag colour', () {
        final backdrop = theme.extension<TenturaFieldBackdropColors>()!;
        expect(
          backdrop,
          TenturaFieldBackdropColors.fromScheme(theme.colorScheme),
        );
        final tags = theme.extension<TenturaTagColors>()!;
        for (final swatch in tags.swatches) {
          expect(backdrop.line, isNot(swatch.accent));
          expect(backdrop.line, isNot(swatch.container));
        }
        // Lines read as a slightly-inked surface: between surface and
        // onSurface in luminance.
        final l = backdrop.line.computeLuminance();
        final s = theme.colorScheme.surface.computeLuminance();
        final o = theme.colorScheme.onSurface.computeLuminance();
        expect(l, inInclusiveRange(math.min(s, o), math.max(s, o)));
      });
    }

    test('light and dark differ, and lerp blends them', () {
      final light = TenturaTheme.light()
          .extension<TenturaFieldBackdropColors>()!;
      final dark = TenturaTheme.dark().extension<TenturaFieldBackdropColors>()!;
      expect(light.line, isNot(dark.line));
      expect(light.lerp(dark, 0), light);
      expect(light.lerp(dark, 1), dark);
      expect(light.lerp(dark, 0.5).line, Color.lerp(light.line, dark.line, 0.5));
      expect(light.copyWith().line, light.line);
    });

    testWidgets('context.fieldBackdropColors reads the theme extension', (
      tester,
    ) async {
      late TenturaFieldBackdropColors colors;
      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.dark(),
          home: Builder(
            builder: (context) {
              colors = context.fieldBackdropColors;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(colors, TenturaTheme.dark().extension<TenturaFieldBackdropColors>());
    });
  });
}
