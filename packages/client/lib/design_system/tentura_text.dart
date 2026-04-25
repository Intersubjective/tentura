import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Named text styles for operational UI. Use via [TenturaTheme] [TextTheme] or
/// these helpers with an explicit [Color].
abstract final class TenturaText {
  /// Card title / name: 14 semibold sans, line height 20/14.
  static TextStyle title(Color color) => GoogleFonts.roboto(
    textStyle: TextStyle(
      color: color,
      fontSize: 14,
      height: 20 / 14,
      fontWeight: FontWeight.w600,
    ),
  );

  /// Body / note: 13 regular sans, line height ~20/13.
  static TextStyle body(Color color) => GoogleFonts.roboto(
    textStyle: TextStyle(
      color: color,
      fontSize: 13,
      height: 20 / 13,
      fontWeight: FontWeight.w400,
    ),
  );

  /// Meta: 11 regular monospace, line height 16/11.
  static TextStyle meta(Color color) => GoogleFonts.robotoMono(
    textStyle: TextStyle(
      color: color,
      fontSize: 11,
      height: 16 / 11,
      fontWeight: FontWeight.w400,
    ),
  );

  /// Status line on cards: 10 semibold sans (Roboto), line height 14/10. Narrower
  /// than monospace so `slot1 · slot2 · slot3` fits on one line. Prefer the
  /// `TenturaStatusText` widget in components for colored status only.
  static TextStyle status(Color color) => GoogleFonts.roboto(
    textStyle: TextStyle(
      color: color,
      fontSize: 10,
      height: 14 / 10,
      fontWeight: FontWeight.w600,
    ),
  );

  /// Command / action: 12 semibold monospace, line height 16/12.
  static TextStyle command(Color color) => GoogleFonts.robotoMono(
    textStyle: TextStyle(
      color: color,
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w600,
    ),
  );

  /// Offer / type: 11 semibold monospace uppercase, letter-spacing ~0.3.
  static TextStyle typeLabel(Color color) => GoogleFonts.robotoMono(
    textStyle: TextStyle(
      color: color,
      fontSize: 11,
      height: 16 / 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.3,
    ),
  );

  /// Tab label: 12 semibold monospace.
  static TextStyle tabLabel(Color color) => GoogleFonts.robotoMono(
    textStyle: TextStyle(
      color: color,
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w600,
    ),
  );
}
