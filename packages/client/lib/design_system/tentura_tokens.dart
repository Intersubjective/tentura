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
    required this.attentionHighlight,
    required this.cardRadius,
    required this.buttonRadius,
    required this.avatarSize,
    required this.iconSize,
    required this.buttonHeight,
    required this.metadataAvatarSize,
    required this.avatarTinySize,
    required this.appBarHeight,
    required this.bottomNavHeight,
    required this.contentMaxWidth,
    required this.chatWideWidth,
    required this.chatColumnMaxWidth,
    required this.bubbleMinWidth,
    required this.bubbleRadiusLarge,
    required this.bubbleRadiusSmall,
    required this.avatarGutter,
    required this.bubbleFarGutter,
    required this.mediaMaxWidth,
    required this.albumGridGap,
    required this.cardPadding,
    required this.cardGap,
    required this.screenHPadding,
    required this.bubbleRowTop,
    required this.rowGap,
    required this.sectionGap,
    required this.iconTextGap,
    required this.avatarTextGap,
    required this.tightGap,
    required this.listRowPadding,
    required this.searchBarHeight,
    required this.searchBarRadius,
    required this.unreadDotSize,
    required this.graphPersonContextWidth,
    required this.graphPersonContextCompactMaxHeightFraction,
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

  /// Border tone for transient attention and changed-field emphasis.
  final Color attentionHighlight;

  final double cardRadius;
  final double buttonRadius;
  final double avatarSize;
  final double iconSize;
  final double buttonHeight;
  final double metadataAvatarSize;
  final double avatarTinySize;
  final double appBarHeight;
  final double bottomNavHeight;

  /// When non-null, root content is constrained (desktop / tablet). `null` = full width.
  final double? contentMaxWidth;

  /// Chat panel width at which room surfaces switch to a centered column.
  final double chatWideWidth;

  /// Max width for the centered room-chat column in wide chat mode.
  final double chatColumnMaxWidth;

  /// Minimum text/media content width for message bubbles.
  final double bubbleMinWidth;

  final double bubbleRadiusLarge;
  final double bubbleRadiusSmall;

  /// Incoming message avatar strip width, kept even when the avatar is hidden.
  final double avatarGutter;

  /// Far-side gutter for outgoing message bubbles.
  ///
  /// Compact uses [TenturaSpacing.screenH] so outgoing bubbles hug the right edge;
  /// regular/expanded keep the wider Telegram-style far margin (56) on the left side.
  final double bubbleFarGutter;

  /// Max content width for media and poll bubbles.
  final double mediaMaxWidth;

  /// Gap for compact album/grid media arrangements.
  final double albumGridGap;

  final EdgeInsets cardPadding;
  final double cardGap;
  final double screenHPadding;
  
  /// Gap between disconnected bubbles in the same list.
  final double bubbleRowTop;

  /// Gap between bubble and avatar / metadata in the list.
  final double rowGap;
  final double sectionGap;
  final double iconTextGap;
  final double avatarTextGap;

  /// Hairline nudge between tightly-related stacked lines. Fixed across classes.
  final double tightGap;

  /// Dense list-row padding (Updates feed). Start/end follow screen vs row gap.
  final EdgeInsets listRowPadding;

  final double searchBarHeight;
  final double searchBarRadius;

  /// Unread glyph badge diameter. Fixed across [WindowClass].
  final double unreadDotSize;

  /// Trust-graph person context panel width on regular/expanded layouts.
  final double graphPersonContextWidth;

  /// Max height fraction for the compact bottom person context card.
  final double graphPersonContextCompactMaxHeightFraction;

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
    attentionHighlight: TenturaPalette.sky,
    cardRadius: TenturaRadii.card,
    buttonRadius: TenturaRadii.button,
    avatarSize: 36,
    iconSize: 22,
    buttonHeight: 44,
    metadataAvatarSize: 24,
    avatarTinySize: 18,
    appBarHeight: 56,
    bottomNavHeight: 64,
    contentMaxWidth: null,
    chatWideWidth: 840,
    chatColumnMaxWidth: 720,
    bubbleMinWidth: 160,
    bubbleRadiusLarge: 16,
    bubbleRadiusSmall: 6,
    avatarGutter: 40,
    bubbleFarGutter: 56,
    mediaMaxWidth: 520,
    albumGridGap: 4,
    cardPadding: TenturaSpacing.cardPaddingAll,
    cardGap: TenturaSpacing.cardGap,
    screenHPadding: TenturaSpacing.screenH,
    bubbleRowTop: 6,
    rowGap: TenturaSpacing.row,
    sectionGap: TenturaSpacing.section,
    iconTextGap: TenturaSpacing.iconText,
    avatarTextGap: TenturaSpacing.avatarText,
    tightGap: TenturaSpacing.tight,
    listRowPadding: TenturaSpacing.listRowPadding,
    searchBarHeight: TenturaSpacing.searchBar,
    searchBarRadius: TenturaRadii.searchBar,
    unreadDotSize: TenturaSpacing.unreadDot,
    graphPersonContextWidth: 320,
    graphPersonContextCompactMaxHeightFraction: 0.42,
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
    attentionHighlight: TenturaPalette.skyDark,
    cardRadius: TenturaRadii.card,
    buttonRadius: TenturaRadii.button,
    avatarSize: 36,
    iconSize: 22,
    buttonHeight: 44,
    metadataAvatarSize: 24,
    avatarTinySize: 18,
    appBarHeight: 56,
    bottomNavHeight: 64,
    contentMaxWidth: null,
    chatWideWidth: 840,
    chatColumnMaxWidth: 720,
    bubbleMinWidth: 160,
    bubbleRadiusLarge: 16,
    bubbleRadiusSmall: 6,
    avatarGutter: 40,
    bubbleFarGutter: 56,
    mediaMaxWidth: 520,
    albumGridGap: 4,
    cardPadding: TenturaSpacing.cardPaddingAll,
    cardGap: TenturaSpacing.cardGap,
    screenHPadding: TenturaSpacing.screenH,
    bubbleRowTop: 6,
    rowGap: TenturaSpacing.row,
    sectionGap: TenturaSpacing.section,
    iconTextGap: TenturaSpacing.iconText,
    avatarTextGap: TenturaSpacing.avatarText,
    tightGap: TenturaSpacing.tight,
    listRowPadding: TenturaSpacing.listRowPadding,
    searchBarHeight: TenturaSpacing.searchBar,
    searchBarRadius: TenturaRadii.searchBar,
    unreadDotSize: TenturaSpacing.unreadDot,
    graphPersonContextWidth: 320,
    graphPersonContextCompactMaxHeightFraction: 0.42,
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
          avatarTinySize: 18,
          appBarHeight: 56,
          bottomNavHeight: 64,
          chatWideWidth: 840,
          chatColumnMaxWidth: 720,
          bubbleMinWidth: 160,
          bubbleRadiusLarge: 16,
          bubbleRadiusSmall: 6,
          avatarGutter: 40,
          // Match near-side padding so outgoing bubbles sit on the right edge
          // (desktop Telegram's 56 far gutter reads as centered on phones).
          bubbleFarGutter: TenturaSpacing.screenH,
          mediaMaxWidth: 520,
          albumGridGap: 4,
          cardPadding: TenturaSpacing.cardPaddingAll,
          cardGap: TenturaSpacing.cardGap,
          screenHPadding: TenturaSpacing.screenH,
          bubbleRowTop: 6,
          rowGap: TenturaSpacing.row,
          sectionGap: TenturaSpacing.section,
          iconTextGap: TenturaSpacing.iconText,
          avatarTextGap: TenturaSpacing.avatarText,
          tightGap: TenturaSpacing.tight,
          listRowPadding: TenturaSpacing.listRowPadding,
          searchBarHeight: TenturaSpacing.searchBar,
          searchBarRadius: TenturaRadii.searchBar,
          unreadDotSize: TenturaSpacing.unreadDot,
          refreshContentMaxWidth: true,
        );
      case WindowClass.regular:
        return copyWith(
          avatarSize: 40,
          iconSize: 24,
          buttonHeight: 46,
          metadataAvatarSize: 26,
          avatarTinySize: 18,
          appBarHeight: 60,
          bottomNavHeight: 72,
          contentMaxWidth: 560,
          chatWideWidth: 840,
          chatColumnMaxWidth: 720,
          bubbleMinWidth: 160,
          bubbleRadiusLarge: 16,
          bubbleRadiusSmall: 6,
          avatarGutter: 40,
          bubbleFarGutter: 56,
          mediaMaxWidth: 520,
          albumGridGap: 4,
      cardPadding: const EdgeInsets.all(14),
      cardGap: 11,
      screenHPadding: 20,
      bubbleRowTop: 6,
      rowGap: 9,
      sectionGap: 14,
          iconTextGap: 7,
          avatarTextGap: 13,
          tightGap: TenturaSpacing.tight,
          listRowPadding: const EdgeInsets.fromLTRB(20, 14, 9, 14),
          searchBarHeight: TenturaSpacing.searchBar,
          searchBarRadius: TenturaRadii.searchBar,
          unreadDotSize: TenturaSpacing.unreadDot,
          refreshContentMaxWidth: true,
        );
      case WindowClass.expanded:
        return copyWith(
          avatarSize: 44,
          iconSize: 26,
          buttonHeight: 48,
          metadataAvatarSize: 28,
          avatarTinySize: 20,
          appBarHeight: 60,
          bottomNavHeight: 72,
          contentMaxWidth: 720,
          chatWideWidth: 840,
          chatColumnMaxWidth: 720,
          bubbleMinWidth: 160,
          bubbleRadiusLarge: 16,
          bubbleRadiusSmall: 6,
          avatarGutter: 40,
          bubbleFarGutter: 56,
          mediaMaxWidth: 640,
          albumGridGap: 4,
      cardPadding: const EdgeInsets.all(16),
      cardGap: 12,
      screenHPadding: 24,
      bubbleRowTop: 6,
      rowGap: 10,
      sectionGap: 16,
          iconTextGap: 8,
          avatarTextGap: 14,
          tightGap: TenturaSpacing.tight,
          listRowPadding: const EdgeInsets.fromLTRB(24, 16, 10, 16),
          searchBarHeight: TenturaSpacing.searchBar,
          searchBarRadius: TenturaRadii.searchBar,
          unreadDotSize: TenturaSpacing.unreadDot,
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
    Color? attentionHighlight,
    double? cardRadius,
    double? buttonRadius,
    double? avatarSize,
    double? iconSize,
    double? buttonHeight,
    double? metadataAvatarSize,
    double? avatarTinySize,
    double? appBarHeight,
    double? bottomNavHeight,
    double? contentMaxWidth,
    double? chatWideWidth,
    double? chatColumnMaxWidth,
    double? bubbleMinWidth,
    double? bubbleRadiusLarge,
    double? bubbleRadiusSmall,
    double? avatarGutter,
    double? bubbleFarGutter,
    double? mediaMaxWidth,
    double? albumGridGap,
    bool refreshContentMaxWidth = false,
    EdgeInsets? cardPadding,
    double? cardGap,
    double? screenHPadding,
    double? bubbleRowTop,
    double? rowGap,
    double? sectionGap,
    double? iconTextGap,
    double? avatarTextGap,
    double? tightGap,
    EdgeInsets? listRowPadding,
    double? searchBarHeight,
    double? searchBarRadius,
    double? unreadDotSize,
    double? graphPersonContextWidth,
    double? graphPersonContextCompactMaxHeightFraction,
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
      attentionHighlight: attentionHighlight ?? this.attentionHighlight,
      cardRadius: cardRadius ?? this.cardRadius,
      buttonRadius: buttonRadius ?? this.buttonRadius,
      avatarSize: avatarSize ?? this.avatarSize,
      iconSize: iconSize ?? this.iconSize,
      buttonHeight: buttonHeight ?? this.buttonHeight,
      metadataAvatarSize: metadataAvatarSize ?? this.metadataAvatarSize,
      avatarTinySize: avatarTinySize ?? this.avatarTinySize,
      appBarHeight: appBarHeight ?? this.appBarHeight,
      bottomNavHeight: bottomNavHeight ?? this.bottomNavHeight,
      contentMaxWidth: refreshContentMaxWidth
          ? contentMaxWidth
          : this.contentMaxWidth,
      chatWideWidth: chatWideWidth ?? this.chatWideWidth,
      chatColumnMaxWidth: chatColumnMaxWidth ?? this.chatColumnMaxWidth,
      bubbleMinWidth: bubbleMinWidth ?? this.bubbleMinWidth,
      bubbleRadiusLarge: bubbleRadiusLarge ?? this.bubbleRadiusLarge,
      bubbleRadiusSmall: bubbleRadiusSmall ?? this.bubbleRadiusSmall,
      avatarGutter: avatarGutter ?? this.avatarGutter,
      bubbleFarGutter: bubbleFarGutter ?? this.bubbleFarGutter,
      mediaMaxWidth: mediaMaxWidth ?? this.mediaMaxWidth,
      albumGridGap: albumGridGap ?? this.albumGridGap,
      cardPadding: cardPadding ?? this.cardPadding,
      cardGap: cardGap ?? this.cardGap,
      screenHPadding: screenHPadding ?? this.screenHPadding,
      bubbleRowTop: bubbleRowTop ?? this.bubbleRowTop,
      rowGap: rowGap ?? this.rowGap,
      sectionGap: sectionGap ?? this.sectionGap,
      iconTextGap: iconTextGap ?? this.iconTextGap,
      avatarTextGap: avatarTextGap ?? this.avatarTextGap,
      tightGap: tightGap ?? this.tightGap,
      listRowPadding: listRowPadding ?? this.listRowPadding,
      searchBarHeight: searchBarHeight ?? this.searchBarHeight,
      searchBarRadius: searchBarRadius ?? this.searchBarRadius,
      unreadDotSize: unreadDotSize ?? this.unreadDotSize,
      graphPersonContextWidth:
          graphPersonContextWidth ?? this.graphPersonContextWidth,
      graphPersonContextCompactMaxHeightFraction:
          graphPersonContextCompactMaxHeightFraction ??
          this.graphPersonContextCompactMaxHeightFraction,
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
      attentionHighlight: Color.lerp(
        attentionHighlight,
        other.attentionHighlight,
        t,
      )!,
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
      avatarTinySize: lerpDouble(avatarTinySize, other.avatarTinySize, t)!,
      appBarHeight: lerpDouble(appBarHeight, other.appBarHeight, t)!,
      bottomNavHeight: lerpDouble(bottomNavHeight, other.bottomNavHeight, t)!,
      contentMaxWidth: _lerpMaxWidth(contentMaxWidth, other.contentMaxWidth, t),
      chatWideWidth: lerpDouble(chatWideWidth, other.chatWideWidth, t)!,
      chatColumnMaxWidth: lerpDouble(
        chatColumnMaxWidth,
        other.chatColumnMaxWidth,
        t,
      )!,
      bubbleMinWidth: lerpDouble(bubbleMinWidth, other.bubbleMinWidth, t)!,
      bubbleRadiusLarge: lerpDouble(bubbleRadiusLarge, other.bubbleRadiusLarge, t)!,
      bubbleRadiusSmall: lerpDouble(bubbleRadiusSmall, other.bubbleRadiusSmall, t)!,
      avatarGutter: lerpDouble(avatarGutter, other.avatarGutter, t)!,
      bubbleFarGutter: lerpDouble(
        bubbleFarGutter,
        other.bubbleFarGutter,
        t,
      )!,
      mediaMaxWidth: lerpDouble(mediaMaxWidth, other.mediaMaxWidth, t)!,
      albumGridGap: lerpDouble(albumGridGap, other.albumGridGap, t)!,
      cardPadding: EdgeInsets.lerp(cardPadding, other.cardPadding, t)!,
      cardGap: lerpDouble(cardGap, other.cardGap, t)!,
      screenHPadding: lerpDouble(screenHPadding, other.screenHPadding, t)!,
      bubbleRowTop: lerpDouble(bubbleRowTop, other.bubbleRowTop, t)!,
      rowGap: lerpDouble(rowGap, other.rowGap, t)!,
      sectionGap: lerpDouble(sectionGap, other.sectionGap, t)!,
      iconTextGap: lerpDouble(iconTextGap, other.iconTextGap, t)!,
      avatarTextGap: lerpDouble(avatarTextGap, other.avatarTextGap, t)!,
      tightGap: lerpDouble(tightGap, other.tightGap, t)!,
      listRowPadding: EdgeInsets.lerp(listRowPadding, other.listRowPadding, t)!,
      searchBarHeight: lerpDouble(searchBarHeight, other.searchBarHeight, t)!,
      searchBarRadius: lerpDouble(searchBarRadius, other.searchBarRadius, t)!,
      unreadDotSize: lerpDouble(unreadDotSize, other.unreadDotSize, t)!,
      graphPersonContextWidth: lerpDouble(
        graphPersonContextWidth,
        other.graphPersonContextWidth,
        t,
      )!,
      graphPersonContextCompactMaxHeightFraction: lerpDouble(
        graphPersonContextCompactMaxHeightFraction,
        other.graphPersonContextCompactMaxHeightFraction,
        t,
      )!,
    );
  }
}

/// Extension accessor for [TenturaTokens].
extension TenturaThemeX on BuildContext {
  TenturaTokens get tt => Theme.of(this).extension<TenturaTokens>()!;

  /// One-shot token read for lifecycles that cannot subscribe to [Theme]
  /// (e.g. provider create callbacks, [State.initState]).
  TenturaTokens get ttOnce =>
      findAncestorWidgetOfExactType<Theme>()!.data.extension<TenturaTokens>()!;
}
