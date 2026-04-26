import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'tentura_colors.dart';
import 'tentura_radii.dart';
import 'tentura_spacing.dart';
import 'tentura_window_class.dart';

/// Tentura-specific tokens (operational UI) not covered well by [ColorScheme] alone.
@immutable
class TenturaTokens extends ThemeExtension<TenturaTokens> {
  const TenturaTokens({
    required this.bg,
    required this.surface,
    required this.border,
    required this.borderSubtle,
    required this.text,
    required this.textMuted,
    required this.textFaint,
    required this.info,
    required this.good,
    required this.warn,
    required this.danger,
    required this.skyBorder,
    required this.cardRadius,
    required this.buttonRadius,
    required this.avatarSize,
    required this.iconSize,
    required this.buttonHeight,
    required this.metadataAvatarSize,
    required this.cardAvatarSize,
    required this.appBarHeight,
    required this.bottomNavHeight,
    required this.contentMaxWidth,
    required this.cardPadding,
    required this.cardGap,
    required this.screenHPadding,
    required this.rowGap,
    required this.sectionGap,
    required this.iconTextGap,
    required this.avatarTextGap,
  });

  final Color bg;
  final Color surface;
  final Color border;
  final Color borderSubtle;

  final Color text;
  final Color textMuted;
  final Color textFaint;

  /// Info / mine / edit (sky family).
  final Color info;
  final Color good;
  final Color warn;
  final Color danger;

  /// Bordered command button outline (sky-tinted).
  final Color skyBorder;

  final double cardRadius;
  final double buttonRadius;
  final double avatarSize;
  final double iconSize;
  final double buttonHeight;
  final double metadataAvatarSize;
  final double cardAvatarSize;
  final double appBarHeight;
  final double bottomNavHeight;

  /// When non-null, root content is constrained (desktop / tablet). `null` = full width.
  final double? contentMaxWidth;

  final EdgeInsets cardPadding;
  final double cardGap;
  final double screenHPadding;
  final double rowGap;
  final double sectionGap;
  final double iconTextGap;
  final double avatarTextGap;

  static const TenturaTokens light = TenturaTokens(
    bg: TenturaPalette.bg,
    surface: TenturaPalette.surface,
    border: TenturaPalette.border,
    borderSubtle: TenturaPalette.borderSubtle,
    text: TenturaPalette.text,
    textMuted: TenturaPalette.textMuted,
    textFaint: TenturaPalette.textFaint,
    info: TenturaPalette.sky,
    good: TenturaPalette.emerald,
    warn: TenturaPalette.amber,
    danger: TenturaPalette.rose,
    skyBorder: TenturaPalette.skyBorder,
    cardRadius: TenturaRadii.card,
    buttonRadius: TenturaRadii.button,
    avatarSize: 36,
    iconSize: 22,
    buttonHeight: 44,
    metadataAvatarSize: 24,
    cardAvatarSize: 40,
    appBarHeight: 56,
    bottomNavHeight: 64,
    contentMaxWidth: null,
    cardPadding: TenturaSpacing.cardPaddingAll,
    cardGap: TenturaSpacing.cardGap,
    screenHPadding: TenturaSpacing.screenH,
    rowGap: TenturaSpacing.row,
    sectionGap: TenturaSpacing.section,
    iconTextGap: TenturaSpacing.iconText,
    avatarTextGap: TenturaSpacing.avatarText,
  );

  static const TenturaTokens dark = TenturaTokens(
    bg: TenturaPalette.bgDark,
    surface: TenturaPalette.surfaceDark,
    border: TenturaPalette.borderDark,
    borderSubtle: TenturaPalette.borderSubtleDark,
    text: TenturaPalette.textDark,
    textMuted: TenturaPalette.textMutedDark,
    textFaint: TenturaPalette.textFaintDark,
    info: TenturaPalette.skyDark,
    good: TenturaPalette.emeraldDark,
    warn: TenturaPalette.amberDark,
    danger: TenturaPalette.roseDark,
    skyBorder: TenturaPalette.skyBorderDark,
    cardRadius: TenturaRadii.card,
    buttonRadius: TenturaRadii.button,
    avatarSize: 36,
    iconSize: 22,
    buttonHeight: 44,
    metadataAvatarSize: 24,
    cardAvatarSize: 40,
    appBarHeight: 56,
    bottomNavHeight: 64,
    contentMaxWidth: null,
    cardPadding: TenturaSpacing.cardPaddingAll,
    cardGap: TenturaSpacing.cardGap,
    screenHPadding: TenturaSpacing.screenH,
    rowGap: TenturaSpacing.row,
    sectionGap: TenturaSpacing.section,
    iconTextGap: TenturaSpacing.iconText,
    avatarTextGap: TenturaSpacing.avatarText,
  );

  /// Mine / secondary info on cards (sky-tinted border emphasis).
  Color get borderMine => skyBorder;

  /// Density for [windowClass]. Colors, radii, and [TextTheme] sizes are unchanged.
  ///
  /// Varies: avatar/icon/button metrics, app bar / bottom nav chrome, [contentMaxWidth],
  /// and spacing tokens ([cardPadding], [cardGap], [screenHPadding], [rowGap],
  /// [sectionGap], [iconTextGap], [avatarTextGap]).
  TenturaTokens applyWindowClass(WindowClass windowClass) {
    switch (windowClass) {
      case WindowClass.compact:
        return copyWith(
          avatarSize: 36,
          iconSize: 22,
          buttonHeight: 44,
          metadataAvatarSize: 24,
          cardAvatarSize: 40,
          appBarHeight: 56,
          bottomNavHeight: 64,
          cardPadding: TenturaSpacing.cardPaddingAll,
          cardGap: TenturaSpacing.cardGap,
          screenHPadding: TenturaSpacing.screenH,
          rowGap: TenturaSpacing.row,
          sectionGap: TenturaSpacing.section,
          iconTextGap: TenturaSpacing.iconText,
          avatarTextGap: TenturaSpacing.avatarText,
          refreshContentMaxWidth: true,
        );
      case WindowClass.regular:
        return copyWith(
          avatarSize: 40,
          iconSize: 24,
          buttonHeight: 46,
          metadataAvatarSize: 26,
          cardAvatarSize: 44,
          appBarHeight: 60,
          bottomNavHeight: 72,
          contentMaxWidth: 560,
          cardPadding: const EdgeInsets.all(14),
          cardGap: 11,
          screenHPadding: 20,
          rowGap: 9,
          sectionGap: 14,
          iconTextGap: 7,
          avatarTextGap: 13,
          refreshContentMaxWidth: true,
        );
      case WindowClass.expanded:
        return copyWith(
          avatarSize: 44,
          iconSize: 26,
          buttonHeight: 48,
          metadataAvatarSize: 28,
          cardAvatarSize: 48,
          appBarHeight: 60,
          bottomNavHeight: 72,
          contentMaxWidth: 720,
          cardPadding: const EdgeInsets.all(16),
          cardGap: 12,
          screenHPadding: 24,
          rowGap: 10,
          sectionGap: 16,
          iconTextGap: 8,
          avatarTextGap: 14,
          refreshContentMaxWidth: true,
        );
    }
  }

  @override
  TenturaTokens copyWith({
    Color? bg,
    Color? surface,
    Color? border,
    Color? borderSubtle,
    Color? text,
    Color? textMuted,
    Color? textFaint,
    Color? info,
    Color? good,
    Color? warn,
    Color? danger,
    Color? skyBorder,
    double? cardRadius,
    double? buttonRadius,
    double? avatarSize,
    double? iconSize,
    double? buttonHeight,
    double? metadataAvatarSize,
    double? cardAvatarSize,
    double? appBarHeight,
    double? bottomNavHeight,
    double? contentMaxWidth,
    bool refreshContentMaxWidth = false,
    EdgeInsets? cardPadding,
    double? cardGap,
    double? screenHPadding,
    double? rowGap,
    double? sectionGap,
    double? iconTextGap,
    double? avatarTextGap,
  }) {
    return TenturaTokens(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      border: border ?? this.border,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      text: text ?? this.text,
      textMuted: textMuted ?? this.textMuted,
      textFaint: textFaint ?? this.textFaint,
      info: info ?? this.info,
      good: good ?? this.good,
      warn: warn ?? this.warn,
      danger: danger ?? this.danger,
      skyBorder: skyBorder ?? this.skyBorder,
      cardRadius: cardRadius ?? this.cardRadius,
      buttonRadius: buttonRadius ?? this.buttonRadius,
      avatarSize: avatarSize ?? this.avatarSize,
      iconSize: iconSize ?? this.iconSize,
      buttonHeight: buttonHeight ?? this.buttonHeight,
      metadataAvatarSize: metadataAvatarSize ?? this.metadataAvatarSize,
      cardAvatarSize: cardAvatarSize ?? this.cardAvatarSize,
      appBarHeight: appBarHeight ?? this.appBarHeight,
      bottomNavHeight: bottomNavHeight ?? this.bottomNavHeight,
      contentMaxWidth: refreshContentMaxWidth
          ? contentMaxWidth
          : this.contentMaxWidth,
      cardPadding: cardPadding ?? this.cardPadding,
      cardGap: cardGap ?? this.cardGap,
      screenHPadding: screenHPadding ?? this.screenHPadding,
      rowGap: rowGap ?? this.rowGap,
      sectionGap: sectionGap ?? this.sectionGap,
      iconTextGap: iconTextGap ?? this.iconTextGap,
      avatarTextGap: avatarTextGap ?? this.avatarTextGap,
    );
  }

  static double? _lerpMaxWidth(double? a, double? b, double t) {
    if (a == null && b == null) return null;
    if (a == null) return b;
    if (b == null) return a;
    return lerpDouble(a, b, t);
  }

  @override
  TenturaTokens lerp(ThemeExtension<TenturaTokens>? other, double t) {
    if (other is! TenturaTokens) return this;
    return TenturaTokens(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      text: Color.lerp(text, other.text, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      info: Color.lerp(info, other.info, t)!,
      good: Color.lerp(good, other.good, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      skyBorder: Color.lerp(skyBorder, other.skyBorder, t)!,
      cardRadius: lerpDouble(cardRadius, other.cardRadius, t)!,
      buttonRadius: lerpDouble(buttonRadius, other.buttonRadius, t)!,
      avatarSize: lerpDouble(avatarSize, other.avatarSize, t)!,
      iconSize: lerpDouble(iconSize, other.iconSize, t)!,
      buttonHeight: lerpDouble(buttonHeight, other.buttonHeight, t)!,
      metadataAvatarSize: lerpDouble(
        metadataAvatarSize,
        other.metadataAvatarSize,
        t,
      )!,
      cardAvatarSize: lerpDouble(cardAvatarSize, other.cardAvatarSize, t)!,
      appBarHeight: lerpDouble(appBarHeight, other.appBarHeight, t)!,
      bottomNavHeight: lerpDouble(bottomNavHeight, other.bottomNavHeight, t)!,
      contentMaxWidth: _lerpMaxWidth(contentMaxWidth, other.contentMaxWidth, t),
      cardPadding: EdgeInsets.lerp(cardPadding, other.cardPadding, t)!,
      cardGap: lerpDouble(cardGap, other.cardGap, t)!,
      screenHPadding: lerpDouble(screenHPadding, other.screenHPadding, t)!,
      rowGap: lerpDouble(rowGap, other.rowGap, t)!,
      sectionGap: lerpDouble(sectionGap, other.sectionGap, t)!,
      iconTextGap: lerpDouble(iconTextGap, other.iconTextGap, t)!,
      avatarTextGap: lerpDouble(avatarTextGap, other.avatarTextGap, t)!,
    );
  }
}

/// Extension accessor for [TenturaTokens].
extension TenturaThemeX on BuildContext {
  TenturaTokens get tt => Theme.of(this).extension<TenturaTokens>()!;
}
