import 'package:flutter/material.dart';

/// Named text styles for operational UI. Use via [TenturaTheme] [TextTheme] or
/// these helpers with an explicit [Color]. Font: **Inter** (bundled).
abstract final class TenturaText {
  static const String _kFontFamily = 'Inter';

  static const FontFeature tabularFigures = FontFeature.tabularFigures();

  static TextStyle withTabular(TextStyle s) =>
      s.copyWith(fontFeatures: const [tabularFigures]);

  static TextStyle _style(
    Color color, {
    required double fontSize,
    required FontWeight fontWeight,
    required double height,
    double letterSpacing = 0,
  }) =>
      TextStyle(
        color: color,
        fontFamily: _kFontFamily,
        fontSize: fontSize,
        fontWeight: fontWeight,
        height: height,
        letterSpacing: letterSpacing,
      );

  /// Card / beacon title (`TextTheme.titleMedium`).
  static TextStyle title(Color color) =>
      _style(color, fontSize: 18, fontWeight: FontWeight.w700, height: 1.22);

  static TextStyle body(Color color) =>
      _style(color, fontSize: 15, fontWeight: FontWeight.w400, height: 1.40);

  static TextStyle bodySmall(Color color) =>
      _style(color, fontSize: 13, fontWeight: FontWeight.w500, height: 1.35);

  /// Status line on cards; prefer `TenturaStatusText` for semantic color only.
  static TextStyle status(Color color) =>
      _style(color, fontSize: 13, fontWeight: FontWeight.w500, height: 1.35);

  static TextStyle command(Color color) =>
      _style(color, fontSize: 15, fontWeight: FontWeight.w700, height: 1.20);

  static TextStyle typeLabel(Color color) => _style(
    color,
    fontSize: 13,
    fontWeight: FontWeight.w700,
    height: 1.35,
    letterSpacing: 0.3,
  );

  static TextStyle tabLabel(Color color) =>
      _style(color, fontSize: 13, fontWeight: FontWeight.w600, height: 1.20);

  /// Bottom navigation labels (only role allowed below 13 logical px).
  static TextStyle navLabel(Color color) =>
      _style(color, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.20);

  // --- Material TextTheme roles (used by TenturaTheme.baseTextTheme) ---

  static TextStyle displayLarge(Color color) =>
      _style(color, fontSize: 32, fontWeight: FontWeight.w700, height: 1.20);

  static TextStyle displayMedium(Color color) =>
      _style(color, fontSize: 28, fontWeight: FontWeight.w700, height: 1.20);

  static TextStyle displaySmall(Color color) =>
      _style(color, fontSize: 24, fontWeight: FontWeight.w700, height: 1.22);

  static TextStyle headlineLarge(Color color) =>
      _style(color, fontSize: 22, fontWeight: FontWeight.w700, height: 1.22);

  static TextStyle headlineMedium(Color color) =>
      _style(color, fontSize: 20, fontWeight: FontWeight.w600, height: 1.25);

  static TextStyle headlineSmall(Color color) =>
      _style(color, fontSize: 18, fontWeight: FontWeight.w600, height: 1.30);

  static TextStyle titleLarge(Color color) =>
      _style(color, fontSize: 20, fontWeight: FontWeight.w700, height: 1.22);

  static TextStyle titleSmall(Color color) =>
      _style(color, fontSize: 15, fontWeight: FontWeight.w600, height: 1.25);

  static TextStyle bodyLarge(Color color) =>
      _style(color, fontSize: 16, fontWeight: FontWeight.w400, height: 1.40);

  static TextStyle bodyMedium(Color color) =>
      _style(color, fontSize: 15, fontWeight: FontWeight.w400, height: 1.40);

  static TextStyle labelLarge(Color color) =>
      _style(color, fontSize: 15, fontWeight: FontWeight.w700, height: 1.20);

  static TextStyle labelMedium(Color color) =>
      _style(color, fontSize: 13, fontWeight: FontWeight.w600, height: 1.20);

  static TextStyle labelSmall(Color color) =>
      _style(color, fontSize: 13, fontWeight: FontWeight.w500, height: 1.35);
}
