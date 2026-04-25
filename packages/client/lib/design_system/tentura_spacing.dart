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

  static const EdgeInsets screenHPadding = EdgeInsets.symmetric(
    horizontal: screenH,
  );
  static const EdgeInsets cardPaddingAll = EdgeInsets.all(cardPadding);
}
