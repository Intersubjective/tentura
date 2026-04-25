import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Local tone + monospace tokens for the Commitments tab (technical canvas style).
class CommitmentToneColors {
  const CommitmentToneColors._({
    required this.neutral,
    required this.good,
    required this.warning,
    required this.danger,
    required this.mine,
    required this.info,
    required this.cardBorder,
    required this.cardBorderMine,
    required this.muted,
  });

  final Color neutral;
  final Color good;
  final Color warning;
  final Color danger;
  final Color mine;
  /// e.g. overlapping / secondary info (not a pill; inline text only).
  final Color info;
  final Color cardBorder;
  final Color cardBorderMine;
  final Color muted;

  factory CommitmentToneColors.of(BuildContext context) {
    if (Theme.of(context).brightness == Brightness.dark) {
      return const CommitmentToneColors._(
        neutral: Color(0xFF94A3B8), // slate-400
        good: Color(0xFF34D399), // emerald-400
        warning: Color(0xFFFBBF24), // amber-400
        danger: Color(0xFFF87171), // rose-400
        mine: Color(0xFF7DD3FC), // sky-300
        info: Color(0xFF93C5FD), // blue-300
        cardBorder: Color(0xFF334155), // slate-700
        cardBorderMine: Color(0xFF0EA5E9), // sky-500
        muted: Color(0xFF94A3B8),
      );
    }
    return const CommitmentToneColors._(
      neutral: Color(0xFF64748B), // slate-500
      good: Color(0xFF059669), // emerald-600
      warning: Color(0xFFD97706), // amber-600
      danger: Color(0xFFE11D48), // rose-600
      mine: Color(0xFF0284C7), // sky-600
      info: Color(0xFF2563EB), // blue-600
      cardBorder: Color(0xFFE2E8F0), // per spec
      cardBorderMine: Color(0xFFBAE6FD), // per spec
      muted: Color(0xFF64748B),
    );
  }
}

TextStyle kCommitmentMonoStatus(BuildContext context, Color color) =>
    kCommitmentMono(
      context,
      color: color,
      fontSize: 11,
      fontWeight: FontWeight.w600,
    );

TextStyle kCommitmentMonoTimestamp(BuildContext context, Color muted) =>
    kCommitmentMono(
      context,
      color: muted,
      fontSize: 11,
      fontWeight: FontWeight.w400,
    );

TextStyle kCommitmentMonoOfferType(BuildContext context, Color color) =>
    kCommitmentMono(
      context,
      color: color,
      fontSize: 11,
      fontWeight: FontWeight.w600,
    );

TextStyle kCommitmentMonoCaption(BuildContext context, Color muted) =>
    kCommitmentMono(
      context,
      color: muted,
      fontSize: 11,
      fontWeight: FontWeight.w400,
    );

TextStyle kCommitmentMonoAction(BuildContext context, Color color) =>
    kCommitmentMono(
      context,
      color: color,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );

TextStyle kCommitmentMono(
  BuildContext context, {
  required Color color,
  required double fontSize,
  required FontWeight fontWeight,
  double height = 1.25,
}) =>
    GoogleFonts.robotoMono(
      textStyle: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
        height: height,
      ),
    );

/// Card shadow: extremely subtle.
List<BoxShadow> kCommitmentCardShadows(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return [
    BoxShadow(
      color: isDark
          ? Colors.black.withValues(alpha: 0.2)
          : Colors.black.withValues(alpha: 0.04),
      blurRadius: 2,
      offset: const Offset(0, 1),
    ),
  ];
}
