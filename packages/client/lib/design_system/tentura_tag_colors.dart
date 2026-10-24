import 'package:flutter/material.dart';

/// Container, on-container text and accent for one person-tag colour.
@immutable
class TenturaTagSwatch {
  const TenturaTagSwatch({
    required this.container,
    required this.onContainer,
    required this.accent,
  });

  final Color container;
  final Color onContainer;

  /// Non-text mark on [container] (glyph circle); keeps ≥ 3:1 against it.
  final Color accent;

  TenturaTagSwatch lerpTo(TenturaTagSwatch other, double t) => TenturaTagSwatch(
    container: Color.lerp(container, other.container, t)!,
    onContainer: Color.lerp(onContainer, other.onContainer, t)!,
    accent: Color.lerp(accent, other.accent, t)!,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TenturaTagSwatch &&
          container == other.container &&
          onContainer == other.onContainer &&
          accent == other.accent;

  @override
  int get hashCode => Object.hash(container, onContainer, accent);
}

/// Person-tag colour palette (colour index 0–7) as a [ThemeExtension].
class TenturaTagColors extends ThemeExtension<TenturaTagColors> {
  const TenturaTagColors({required this.swatches});

  static const swatchCount = 8;

  final List<TenturaTagSwatch> swatches;

  static const light = TenturaTagColors(
    swatches: [
      TenturaTagSwatch(
        container: Color(0xFFFEE2E2),
        onContainer: Color(0xFF991B1B),
        accent: Color(0xFFDC2626),
      ),
      TenturaTagSwatch(
        container: Color(0xFFFFEDD5),
        onContainer: Color(0xFF9A3412),
        accent: Color(0xFFC2410C),
      ),
      TenturaTagSwatch(
        container: Color(0xFFFEF3C7),
        onContainer: Color(0xFF78350F),
        accent: Color(0xFFB45309),
      ),
      TenturaTagSwatch(
        container: Color(0xFFDCFCE7),
        onContainer: Color(0xFF166534),
        accent: Color(0xFF15803D),
      ),
      TenturaTagSwatch(
        container: Color(0xFFCCFBF1),
        onContainer: Color(0xFF115E59),
        accent: Color(0xFF0F766E),
      ),
      TenturaTagSwatch(
        container: Color(0xFFDBEAFE),
        onContainer: Color(0xFF1E40AF),
        accent: Color(0xFF2563EB),
      ),
      TenturaTagSwatch(
        container: Color(0xFFEDE9FE),
        onContainer: Color(0xFF5B21B6),
        accent: Color(0xFF7C3AED),
      ),
      TenturaTagSwatch(
        container: Color(0xFFFCE7F3),
        onContainer: Color(0xFF9D174D),
        accent: Color(0xFFDB2777),
      ),
    ],
  );

  static const dark = TenturaTagColors(
    swatches: [
      TenturaTagSwatch(
        container: Color(0xFF4A1D1D),
        onContainer: Color(0xFFFECACA),
        accent: Color(0xFFF87171),
      ),
      TenturaTagSwatch(
        container: Color(0xFF44250F),
        onContainer: Color(0xFFFED7AA),
        accent: Color(0xFFFB923C),
      ),
      TenturaTagSwatch(
        container: Color(0xFF422D0A),
        onContainer: Color(0xFFFDE68A),
        accent: Color(0xFFFBBF24),
      ),
      TenturaTagSwatch(
        container: Color(0xFF14391F),
        onContainer: Color(0xFFBBF7D0),
        accent: Color(0xFF4ADE80),
      ),
      TenturaTagSwatch(
        container: Color(0xFF123A38),
        onContainer: Color(0xFF99F6E4),
        accent: Color(0xFF2DD4BF),
      ),
      TenturaTagSwatch(
        container: Color(0xFF1E2F55),
        onContainer: Color(0xFFBFDBFE),
        accent: Color(0xFF60A5FA),
      ),
      TenturaTagSwatch(
        container: Color(0xFF362158),
        onContainer: Color(0xFFDDD6FE),
        accent: Color(0xFFA78BFA),
      ),
      TenturaTagSwatch(
        container: Color(0xFF4C1D36),
        onContainer: Color(0xFFFBCFE8),
        accent: Color(0xFFF472B6),
      ),
    ],
  );

  /// Swatch for a stored colour index; out-of-range indexes wrap.
  TenturaTagSwatch swatchFor(int colorIndex) =>
      swatches[colorIndex % swatchCount];

  @override
  TenturaTagColors copyWith({List<TenturaTagSwatch>? swatches}) =>
      TenturaTagColors(swatches: swatches ?? this.swatches);

  @override
  TenturaTagColors lerp(ThemeExtension<TenturaTagColors>? other, double t) {
    if (other is! TenturaTagColors) return this;
    if (t <= 0) return this;
    if (t >= 1) return other;
    return TenturaTagColors(
      swatches: [
        for (var i = 0; i < swatchCount; i++)
          swatches[i].lerpTo(other.swatches[i], t),
      ],
    );
  }
}

extension TenturaTagColorsX on BuildContext {
  /// Fail-fast access; callers must sit under `TenturaTheme`.
  TenturaTagColors get tagColors =>
      Theme.of(this).extension<TenturaTagColors>()!;
}
