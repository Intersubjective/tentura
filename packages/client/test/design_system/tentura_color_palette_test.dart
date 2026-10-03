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
  for (final (name, p) in [
    ('light', TenturaColorPalette.light),
    ('dark', TenturaColorPalette.dark),
  ]) {
    group('TenturaColorPalette.$name', () {
      // These floors are the re-theming contract documented on the class: a
      // palette edit that breaks readability fails here, not in review.
      test('text tiers are readable on bg and surface', () {
        for (final bg in [p.bg, p.surface]) {
          expect(_contrast(p.text, bg), greaterThanOrEqualTo(4.5));
          expect(_contrast(p.textMuted, bg), greaterThanOrEqualTo(4.5));
          expect(_contrast(p.textFaint, bg), greaterThanOrEqualTo(3));
        }
      });

      test('brand pairs are readable', () {
        expect(_contrast(p.onBrand, p.brand), greaterThanOrEqualTo(4.5));
        expect(
          _contrast(p.onBrandContainer, p.brandContainer),
          greaterThanOrEqualTo(4.5),
        );
        // Brand doubles as link / info ink on page and card backgrounds.
        expect(_contrast(p.brand, p.bg), greaterThanOrEqualTo(4.5));
        expect(_contrast(p.brand, p.surface), greaterThanOrEqualTo(4.5));
      });

      test('semantic tones are readable', () {
        for (final tone in [p.good, p.warn, p.danger]) {
          expect(_contrast(tone, p.surface), greaterThanOrEqualTo(4.5));
        }
        expect(
          _contrast(p.onGoodContainer, p.goodContainer),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(p.onWarnContainer, p.warnContainer),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(p.onDangerContainer, p.dangerContainer),
          greaterThanOrEqualTo(4.5),
        );
        expect(_contrast(p.onDanger, p.danger), greaterThanOrEqualTo(4.5));
      });

      test('avatar hues and capability swatches are readable', () {
        expect(p.avatarHues, hasLength(greaterThanOrEqualTo(6)));
        for (final hue in p.avatarHues) {
          expect(
            _contrast(hue.onContainer, hue.container),
            greaterThanOrEqualTo(4.5),
          );
        }
        for (final group in [
          p.capabilities.logistics,
          p.capabilities.communication,
          p.capabilities.knowledge,
          p.capabilities.care,
          p.capabilities.resources,
          p.capabilities.technical,
          p.capabilities.rpg,
          p.capabilities.special,
        ]) {
          expect(
            _contrast(group.onContainer, group.container),
            greaterThanOrEqualTo(4.5),
          );
        }
      });

      test('ColorScheme maps every brand / neutral role from the palette', () {
        final scheme = p.toColorScheme();
        expect(scheme.brightness, p.brightness);
        expect(scheme.primary, p.brand);
        expect(scheme.onPrimary, p.onBrand);
        expect(scheme.primaryContainer, p.brandContainer);
        expect(scheme.secondaryContainer, p.brandContainer);
        expect(scheme.tertiary, p.good);
        expect(scheme.error, p.danger);
        expect(scheme.surface, p.bg);
        expect(scheme.surfaceContainer, p.surface);
        expect(scheme.surfaceContainerHigh, p.surfaceSunken);
        expect(scheme.onSurface, p.text);
        expect(scheme.onSurfaceVariant, p.textMuted);
        expect(scheme.outline, p.border);
        expect(scheme.outlineVariant, p.borderStrong);
      });

      test('theme, tokens and capability colours all come from it', () {
        final theme = TenturaTheme.fromPalette(p);
        final tokens = theme.extension<TenturaTokens>()!;
        expect(theme.colorScheme.primary, p.brand);
        expect(tokens.bg, p.bg);
        expect(tokens.surface, p.surface);
        expect(tokens.text, p.text);
        expect(tokens.info, p.brand);
        expect(tokens.good, p.good);
        expect(tokens.danger, p.danger);
        expect(theme.extension<TenturaCapabilityColors>(), p.capabilities);
      });
    });
  }

  test('a re-themed palette flows through the whole theme', () {
    const brand = Color(0xFF7C3AED);
    final custom = TenturaColorPalette(
      brightness: Brightness.light,
      brand: brand,
      onBrand: const Color(0xFFFFFFFF),
      brandContainer: const Color(0xFFEDE9FE),
      onBrandContainer: const Color(0xFF5B21B6),
      brandBorder: const Color(0xFFDDD6FE),
      bg: TenturaColorPalette.light.bg,
      surface: TenturaColorPalette.light.surface,
      surfaceSunken: TenturaColorPalette.light.surfaceSunken,
      surfaceSunkenStrong: TenturaColorPalette.light.surfaceSunkenStrong,
      border: TenturaColorPalette.light.border,
      borderSubtle: TenturaColorPalette.light.borderSubtle,
      borderStrong: TenturaColorPalette.light.borderStrong,
      text: TenturaColorPalette.light.text,
      textMuted: TenturaColorPalette.light.textMuted,
      textFaint: TenturaColorPalette.light.textFaint,
      good: TenturaColorPalette.light.good,
      goodContainer: TenturaColorPalette.light.goodContainer,
      onGoodContainer: TenturaColorPalette.light.onGoodContainer,
      warn: TenturaColorPalette.light.warn,
      warnContainer: TenturaColorPalette.light.warnContainer,
      onWarnContainer: TenturaColorPalette.light.onWarnContainer,
      danger: TenturaColorPalette.light.danger,
      onDanger: TenturaColorPalette.light.onDanger,
      dangerContainer: TenturaColorPalette.light.dangerContainer,
      onDangerContainer: TenturaColorPalette.light.onDangerContainer,
      scrim: TenturaColorPalette.light.scrim,
      avatarHues: TenturaColorPalette.light.avatarHues,
      capabilities: TenturaColorPalette.light.capabilities,
    );
    final theme = TenturaTheme.fromPalette(custom);
    expect(theme.colorScheme.primary, brand);
    expect(theme.extension<TenturaTokens>()!.info, brand);
    expect(theme.navigationBarTheme.indicatorColor, custom.brandContainer);
    expect(theme.badgeTheme.backgroundColor, brand);
  });

  group('avatarHueFor', () {
    test('is stable for the same key', () {
      const p = TenturaColorPalette.light;
      expect(p.avatarHueFor('U9828d11a1555'), p.avatarHueFor('U9828d11a1555'));
    });

    test('spreads look-alike ids across the hue set', () {
      const p = TenturaColorPalette.light;
      final used = {
        for (var i = 0; i < 64; i++)
          p.avatarHues.indexOf(
            p.avatarHueFor('U${i.toRadixString(16).padLeft(12, '0')}'),
          ),
      };
      expect(used.length, p.avatarHues.length);
    });

    test('matches the reference FNV-1a + finaliser values', () {
      // Pinned so web (JS doubles), wasm and native agree on a person's hue.
      const p = TenturaColorPalette.light;
      final indices = [
        for (final id in [
          'Ufd5a20b6d581',
          'U3be0418e51a3',
          'U5fd6d2c16ce6',
          'U9828d11a1555',
          'Ud6eafcf973d8',
          'Ucfc5f775514b',
        ])
          p.avatarHues.indexOf(p.avatarHueFor(id)),
      ];
      expect(indices, [5, 2, 3, 5, 4, 1]);
    });
  });
}
