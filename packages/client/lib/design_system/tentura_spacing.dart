import 'package:flutter/material.dart';

/// Spacing and padding tokens for 360px-first operational density.
abstract final class TenturaSpacing {
  static const double screenH = 16;
  static const double listTop = 8;
  static const double listBottom = 24;
  static const double cardPadding = 12;
  static const double cardGap = 10;
  static const double row = 8;
  static const double section = 12;
  static const double iconText = 6;
  static const double avatarText = 12;

  /// Hairline nudge between tightly-related stacked lines (e.g. metadata rows).
  /// Intentionally fixed — does not scale with [WindowClass].
  static const double tight = 2;

  /// M3 search-field height on Updates and similar list screens.
  static const double searchBar = 48;

  /// Unread indicator on a list-row leading glyph.
  static const double unreadDot = 10;

  /// Compact Updates / record-list row: start screenH, vertical card, end row.
  static const EdgeInsets listRowPadding = EdgeInsets.fromLTRB(
    screenH,
    cardPadding,
    row,
    cardPadding,
  );

  static const EdgeInsets screenHPadding = EdgeInsets.symmetric(
    horizontal: screenH,
  );
  static const EdgeInsets cardPaddingAll = EdgeInsets.all(cardPadding);
}
