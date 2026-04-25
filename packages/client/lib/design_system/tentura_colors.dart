import 'package:flutter/material.dart';

/// Raw palette reference (documentation + one-off use inside design system only).
abstract final class TenturaPalette {
  // Light spec
  static const Color bg = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE2E8F0);
  static const Color borderSubtle = Color(0xFFF1F5F9);
  static const Color text = Color(0xFF0F172A);
  static const Color textMuted = Color(0xFF64748B);
  static const Color textFaint = Color(0xFF94A3B8);
  static const Color sky = Color(0xFF0369A1);
  static const Color skyBorder = Color(0xFFBAE6FD);
  static const Color skyBorderAlt = Color(0xFFE0F2FE);
  static const Color emerald = Color(0xFF047857);
  static const Color amber = Color(0xFFB45309);
  static const Color rose = Color(0xFFBE123C);

  // Dark: operational tints (aligned with [CommitmentToneColors] dark where useful)
  static const Color textDark = Color(0xFFE1E1E1);
  static const Color textMutedDark = Color(0xFF94A3B8);
  static const Color textFaintDark = Color(0xFF64748B);
  static const Color bgDark = Color(0xFF0A1826);
  static const Color surfaceDark = Color(0xFF1D2935);
  static const Color borderDark = Color(0xFF334155);
  static const Color borderSubtleDark = Color(0xFF1E293B);
  static const Color skyDark = Color(0xFF7DD3FC);
  static const Color emeraldDark = Color(0xFF34D399);
  static const Color amberDark = Color(0xFFFBBF24);
  static const Color roseDark = Color(0xFFF87171);
  static const Color infoDark = Color(0xFF93C5FD);
  static const Color skyBorderDark = Color(0xFF0EA5E9);
}
