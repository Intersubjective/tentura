import 'package:flutter/material.dart';

/// Field topographic backdrop colours (#1022) as a [ThemeExtension].
///
/// Derived from the M3 surface roles only: the contour line is the Field
/// surface ([ColorScheme.surface]) inked a few percent towards
/// [ColorScheme.onSurface], so it reads at ~1.15:1 against the surface in
/// both themes and always stays below tag hulls, the unread glow, edges and
/// rings. Never tinted by tag colours. Opaque: the backdrop is drawn with
/// this colour as is, so feature code carries no alpha of its own.
/// `test/design_system/tentura_field_backdrop_colors_test.dart` holds the
/// contrast to 1.05–1.25:1.
@immutable
class TenturaFieldBackdropColors
    extends ThemeExtension<TenturaFieldBackdropColors> {
  const TenturaFieldBackdropColors({required this.line});

  /// Colours for [scheme], mixed from its surface roles.
  factory TenturaFieldBackdropColors.fromScheme(ColorScheme scheme) =>
      TenturaFieldBackdropColors(
        line: Color.lerp(
          scheme.surface,
          scheme.onSurface,
          scheme.brightness == Brightness.dark ? _inkDark : _inkLight,
        )!,
      );

  /// Share of onSurface mixed into the surface for the line (light: ~1.18:1).
  static const _inkLight = 0.08;

  /// Share of onSurface mixed into the surface for the line (dark: ~1.15:1).
  static const _inkDark = 0.065;

  /// Contour line colour.
  final Color line;

  @override
  TenturaFieldBackdropColors copyWith({Color? line}) =>
      TenturaFieldBackdropColors(line: line ?? this.line);

  @override
  TenturaFieldBackdropColors lerp(
    ThemeExtension<TenturaFieldBackdropColors>? other,
    double t,
  ) {
    if (other is! TenturaFieldBackdropColors) return this;
    if (t <= 0) return this;
    if (t >= 1) return other;
    return TenturaFieldBackdropColors(line: Color.lerp(line, other.line, t)!);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TenturaFieldBackdropColors && line == other.line;

  @override
  int get hashCode => line.hashCode;
}

extension TenturaFieldBackdropColorsX on BuildContext {
  /// Fail-fast access; callers must sit under `TenturaTheme`.
  TenturaFieldBackdropColors get fieldBackdropColors =>
      Theme.of(this).extension<TenturaFieldBackdropColors>()!;
}
