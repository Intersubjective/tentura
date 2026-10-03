import 'package:flutter/material.dart';

import 'tentura_capability_colors.dart';

/// Container + on-container pair (avatar hues, capability groups, …).
typedef TenturaSwatch = CapabilitySwatch;

/// THE colour source of truth for the Tentura client.
///
/// Every colour the app paints is defined once here, for light and dark.
/// `TenturaTheme` builds the full Material [ColorScheme] from it (no
/// `ColorScheme.fromSeed` — every role is mapped explicitly, see
/// [toColorScheme]) and `TenturaTokens` / [TenturaCapabilityColors] read their
/// colours from it. Feature code never sees these hex values directly: it uses
/// `Theme.of(context).colorScheme.*` or `context.tt.*`.
///
/// ## Re-theming
///
/// * **Change the brand colour:** edit [brand], [onBrand], [brandContainer],
///   [onBrandContainer] and [brandBorder] in [light] and [dark]. Buttons,
///   links, selection, focus, nav indicators, outgoing chat bubbles and the
///   "info" tone all follow.
/// * **Change the neutral feel** (cool slate today): edit the surface, border
///   and text tiers.
/// * Keep contrast: `text`/`textMuted` ≥ 4.5:1 on [bg] and [surface];
///   `onBrand` ≥ 4.5:1 on [brand]; each `on*Container` ≥ 4.5:1 on its
///   container. `test/design_system/tentura_color_palette_test.dart` enforces
///   this, so a palette edit that breaks readability fails CI.
@immutable
class TenturaColorPalette {
  const TenturaColorPalette({
    required this.brightness,
    required this.brand,
    required this.onBrand,
    required this.brandContainer,
    required this.onBrandContainer,
    required this.brandBorder,
    required this.bg,
    required this.surface,
    required this.surfaceSunken,
    required this.surfaceSunkenStrong,
    required this.border,
    required this.borderSubtle,
    required this.borderStrong,
    required this.text,
    required this.textMuted,
    required this.textFaint,
    required this.good,
    required this.goodContainer,
    required this.onGoodContainer,
    required this.warn,
    required this.warnContainer,
    required this.onWarnContainer,
    required this.danger,
    required this.onDanger,
    required this.dangerContainer,
    required this.onDangerContainer,
    required this.scrim,
    required this.avatarHues,
    required this.capabilities,
  });

  final Brightness brightness;

  // --- Brand -----------------------------------------------------------------

  /// Primary actions, links, selection, focus and the "info" tone.
  final Color brand;

  /// Text / icons on [brand].
  final Color onBrand;

  /// Tonal fills: secondary buttons, nav indicator, outgoing chat bubble.
  final Color brandContainer;

  /// Text / icons on [brandContainer].
  final Color onBrandContainer;

  /// Hairline that marks "mine" / brand-tinted outlines.
  final Color brandBorder;

  // --- Neutrals --------------------------------------------------------------

  /// Scaffold / page background.
  final Color bg;

  /// Cards, sheets, dialogs, bars.
  final Color surface;

  /// Recessed fills on [surface]: incoming bubbles, inputs, hover.
  final Color surfaceSunken;

  /// Stronger recessed fill: tracks, skeletons, avatar fallback.
  final Color surfaceSunkenStrong;

  /// Card and field borders.
  final Color border;

  /// Dividers inside a card.
  final Color borderSubtle;

  /// Emphasised outlines (outlined buttons, unselected controls' frames).
  final Color borderStrong;

  final Color text;

  /// Secondary text (≥ 4.5:1).
  final Color textMuted;

  /// Hints, decorative glyphs (≥ 3:1).
  final Color textFaint;

  // --- Semantic tones --------------------------------------------------------

  final Color good;
  final Color goodContainer;
  final Color onGoodContainer;
  final Color warn;
  final Color warnContainer;
  final Color onWarnContainer;
  final Color danger;
  final Color onDanger;
  final Color dangerContainer;
  final Color onDangerContainer;

  final Color scrim;

  /// Deterministic per-person colours for initials avatars.
  final List<TenturaSwatch> avatarHues;

  /// Capability-group tints.
  final TenturaCapabilityColors capabilities;

  /// Alias: info tone == brand.
  Color get info => brand;

  /// Picks a stable avatar hue for [key] (usually a user id).
  TenturaSwatch avatarHueFor(String key) {
    // FNV-1a + a 32-bit finaliser: ids share long prefixes, and a plain
    // polynomial hash clustered them on two or three hues.
    var hash = 0x811c9dc5;
    for (final unit in key.codeUnits) {
      hash = _mul32(hash ^ unit, 0x01000193);
    }
    hash ^= hash >> 16;
    hash = _mul32(hash, 0x7feb352d);
    hash ^= hash >> 15;
    hash = _mul32(hash, 0x846ca68b);
    hash ^= hash >> 16;
    return avatarHues[hash % avatarHues.length];
  }

  /// 32-bit wrapping multiply that stays exact on the JS target (doubles):
  /// no intermediate exceeds 2^48.
  static int _mul32(int a, int b) {
    final lo = (a & 0xffff) * b;
    final hi = (((a >> 16) & 0xffff) * b) & 0xffff;
    return (lo + (hi << 16)) & 0xffffffff;
  }

  /// Full Material 3 [ColorScheme]; every role is mapped explicitly.
  ColorScheme toColorScheme() => ColorScheme(
    brightness: brightness,
    primary: brand,
    onPrimary: onBrand,
    primaryContainer: brandContainer,
    onPrimaryContainer: onBrandContainer,
    primaryFixed: brandContainer,
    primaryFixedDim: brandBorder,
    onPrimaryFixed: onBrandContainer,
    onPrimaryFixedVariant: onBrandContainer,
    // Secondary = the brand's tonal tier: Filled.tonal buttons, selected
    // chips / segments. Keeps every "selected" and "secondary action" fill in
    // one hue family instead of a seed-derived grey-blue.
    secondary: brand,
    onSecondary: onBrand,
    secondaryContainer: brandContainer,
    onSecondaryContainer: onBrandContainer,
    secondaryFixed: brandContainer,
    secondaryFixedDim: brandBorder,
    onSecondaryFixed: onBrandContainer,
    onSecondaryFixedVariant: onBrandContainer,
    // Tertiary = positive outcome ("enough help", "useful").
    tertiary: good,
    onTertiary: surface,
    tertiaryContainer: goodContainer,
    onTertiaryContainer: onGoodContainer,
    tertiaryFixed: goodContainer,
    tertiaryFixedDim: goodContainer,
    onTertiaryFixed: onGoodContainer,
    onTertiaryFixedVariant: onGoodContainer,
    error: danger,
    onError: onDanger,
    errorContainer: dangerContainer,
    onErrorContainer: onDangerContainer,
    surface: bg,
    onSurface: text,
    onSurfaceVariant: textMuted,
    surfaceDim: surfaceSunken,
    surfaceBright: surface,
    surfaceContainerLowest: surface,
    surfaceContainerLow: surface,
    surfaceContainer: surface,
    surfaceContainerHigh: surfaceSunken,
    surfaceContainerHighest: surfaceSunkenStrong,
    // Tentura convention (pre-dates this palette): `outline` is the light card
    // hairline, `outlineVariant` the stronger frame.
    outline: border,
    outlineVariant: borderStrong,
    shadow: scrim,
    scrim: scrim,
    inverseSurface: text,
    onInverseSurface: bg,
    inversePrimary: brandBorder,
    surfaceTint: Colors.transparent,
  );

  // ===========================================================================
  // LIGHT
  // ===========================================================================

  static const light = TenturaColorPalette(
    brightness: Brightness.light,
    brand: Color(0xFF0369A1),
    onBrand: Color(0xFFFFFFFF),
    brandContainer: Color(0xFFE0F2FE),
    onBrandContainer: Color(0xFF075985),
    brandBorder: Color(0xFFBAE6FD),
    bg: Color(0xFFF8FAFC),
    surface: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFF1F5F9),
    surfaceSunkenStrong: Color(0xFFE2E8F0),
    border: Color(0xFFE2E8F0),
    borderSubtle: Color(0xFFF1F5F9),
    borderStrong: Color(0xFFCBD5E1),
    text: Color(0xFF0F172A),
    textMuted: Color(0xFF64748B),
    textFaint: Color(0xFF748399),
    good: Color(0xFF047857),
    goodContainer: Color(0xFFD1FAE5),
    onGoodContainer: Color(0xFF065F46),
    warn: Color(0xFFB45309),
    warnContainer: Color(0xFFFEF3C7),
    onWarnContainer: Color(0xFF92400E),
    danger: Color(0xFFBE123C),
    onDanger: Color(0xFFFFFFFF),
    dangerContainer: Color(0xFFFFE4E6),
    onDangerContainer: Color(0xFF9F1239),
    scrim: Color(0xFF000000),
    avatarHues: [
      TenturaSwatch(
        container: Color(0xFFE0F2FE),
        onContainer: Color(0xFF075985),
      ),
      TenturaSwatch(
        container: Color(0xFFE0E7FF),
        onContainer: Color(0xFF3730A3),
      ),
      TenturaSwatch(
        container: Color(0xFFEDE9FE),
        onContainer: Color(0xFF5B21B6),
      ),
      TenturaSwatch(
        container: Color(0xFFFCE7F3),
        onContainer: Color(0xFF9D174D),
      ),
      TenturaSwatch(
        container: Color(0xFFFEF3C7),
        onContainer: Color(0xFF92400E),
      ),
      TenturaSwatch(
        container: Color(0xFFD1FAE5),
        onContainer: Color(0xFF065F46),
      ),
      TenturaSwatch(
        container: Color(0xFFCCFBF1),
        onContainer: Color(0xFF115E59),
      ),
      TenturaSwatch(
        container: Color(0xFFFFEDD5),
        onContainer: Color(0xFF9A3412),
      ),
    ],
    capabilities: TenturaCapabilityColors(
      logistics: TenturaSwatch(
        container: Color(0xFFEEF2FF),
        onContainer: Color(0xFF3730A3),
      ),
      communication: TenturaSwatch(
        container: Color(0xFFECFEFF),
        onContainer: Color(0xFF155E75),
      ),
      knowledge: TenturaSwatch(
        container: Color(0xFFF5F3FF),
        onContainer: Color(0xFF5B21B6),
      ),
      care: TenturaSwatch(
        container: Color(0xFFFDF4FF),
        onContainer: Color(0xFF86198F),
      ),
      resources: TenturaSwatch(
        container: Color(0xFFF0FDFA),
        onContainer: Color(0xFF115E59),
      ),
      technical: TenturaSwatch(
        container: Color(0xFFF5F5F4),
        onContainer: Color(0xFF44403C),
      ),
      rpg: TenturaSwatch(
        container: Color(0xFFFFFBEB),
        onContainer: Color(0xFF78350F),
      ),
      special: TenturaSwatch(
        container: Color(0xFFF1F5F9),
        onContainer: Color(0xFF475569),
      ),
    ),
  );

  // ===========================================================================
  // DARK
  // ===========================================================================

  static const dark = TenturaColorPalette(
    brightness: Brightness.dark,
    brand: Color(0xFF38BDF8),
    onBrand: Color(0xFF04263A),
    brandContainer: Color(0xFF0C3550),
    onBrandContainer: Color(0xFFBAE6FD),
    brandBorder: Color(0xFF0E5A85),
    bg: Color(0xFF0A1826),
    surface: Color(0xFF132231),
    surfaceSunken: Color(0xFF1B2B3B),
    surfaceSunkenStrong: Color(0xFF253647),
    border: Color(0xFF2A3B4D),
    borderSubtle: Color(0xFF1C2C3C),
    borderStrong: Color(0xFF3B4D61),
    text: Color(0xFFE2E8F0),
    textMuted: Color(0xFF94A3B8),
    textFaint: Color(0xFF6B7C93),
    good: Color(0xFF34D399),
    goodContainer: Color(0xFF0F3D30),
    onGoodContainer: Color(0xFFA7F3D0),
    warn: Color(0xFFFBBF24),
    warnContainer: Color(0xFF43300C),
    onWarnContainer: Color(0xFFFDE68A),
    danger: Color(0xFFF87171),
    onDanger: Color(0xFF0A1826),
    dangerContainer: Color(0xFF4A1A22),
    onDangerContainer: Color(0xFFFECDD3),
    scrim: Color(0xFF000000),
    avatarHues: [
      TenturaSwatch(
        container: Color(0xFF0C3550),
        onContainer: Color(0xFFBAE6FD),
      ),
      TenturaSwatch(
        container: Color(0xFF272E5C),
        onContainer: Color(0xFFC7D2FE),
      ),
      TenturaSwatch(
        container: Color(0xFF33265A),
        onContainer: Color(0xFFDDD6FE),
      ),
      TenturaSwatch(
        container: Color(0xFF4A1D35),
        onContainer: Color(0xFFFBCFE8),
      ),
      TenturaSwatch(
        container: Color(0xFF43300C),
        onContainer: Color(0xFFFDE68A),
      ),
      TenturaSwatch(
        container: Color(0xFF0F3D30),
        onContainer: Color(0xFFA7F3D0),
      ),
      TenturaSwatch(
        container: Color(0xFF0F3B39),
        onContainer: Color(0xFF99F6E4),
      ),
      TenturaSwatch(
        container: Color(0xFF44250F),
        onContainer: Color(0xFFFED7AA),
      ),
    ],
    capabilities: TenturaCapabilityColors(
      logistics: TenturaSwatch(
        container: Color(0xFF252F4A),
        onContainer: Color(0xFFA5B4FC),
      ),
      communication: TenturaSwatch(
        container: Color(0xFF16323C),
        onContainer: Color(0xFF67E8F9),
      ),
      knowledge: TenturaSwatch(
        container: Color(0xFF2A2647),
        onContainer: Color(0xFFC4B5FD),
      ),
      care: TenturaSwatch(
        container: Color(0xFF3A1F3F),
        onContainer: Color(0xFFF0ABFC),
      ),
      resources: TenturaSwatch(
        container: Color(0xFF123832),
        onContainer: Color(0xFF5EEAD4),
      ),
      technical: TenturaSwatch(
        container: Color(0xFF292524),
        onContainer: Color(0xFFD6D3D1),
      ),
      rpg: TenturaSwatch(
        container: Color(0xFF3B2710),
        onContainer: Color(0xFFFBBF24),
      ),
      special: TenturaSwatch(
        container: Color(0xFF273240),
        onContainer: Color(0xFFCBD5E1),
      ),
    ),
  );

  static TenturaColorPalette of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}

/// Palette for the ambient theme brightness (avatar hues, swatches).
extension TenturaPaletteX on BuildContext {
  TenturaColorPalette get palette =>
      TenturaColorPalette.of(Theme.of(this).colorScheme.brightness);
}
