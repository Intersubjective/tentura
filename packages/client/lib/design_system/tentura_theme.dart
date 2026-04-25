import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tentura_colors.dart';
import 'tentura_radii.dart';
import 'tentura_text.dart';
import 'tentura_tokens.dart';

/// Root [ThemeData] for Tentura: Material 3 + [TenturaTokens] extension.
abstract final class TenturaTheme {
  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: TenturaPalette.sky,
    ).copyWith(
      surface: TenturaPalette.bg,
      surfaceContainer: TenturaPalette.surface,
      onSurface: TenturaPalette.text,
      onSurfaceVariant: TenturaPalette.textMuted,
      outline: TenturaPalette.border,
      error: TenturaPalette.rose,
      onError: Colors.white,
    );

    return _base(
      colorScheme: colorScheme,
      tokens: TenturaTokens.light,
    );
  }

  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: TenturaPalette.skyDark,
      brightness: Brightness.dark,
    ).copyWith(
      surface: TenturaPalette.bgDark,
      surfaceContainer: TenturaPalette.surfaceDark,
      onSurface: TenturaPalette.textDark,
      onSurfaceVariant: TenturaPalette.textMutedDark,
      outline: TenturaPalette.borderDark,
      error: TenturaPalette.roseDark,
      onError: const Color(0xFF0A1826),
    );

    return _base(
      colorScheme: colorScheme,
      tokens: TenturaTokens.dark,
    );
  }

  static ThemeData _base({
    required ColorScheme colorScheme,
    required TenturaTokens tokens,
  }) {
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(tokens.buttonRadius),
    );

    final expansionTileShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(TenturaRadii.button),
      side: BorderSide(color: colorScheme.outline),
    );

    final onSurface = colorScheme.onSurface;
    final textTheme = GoogleFonts.robotoTextTheme(
      baseTextTheme(
        onSurface: onSurface,
        onSurfaceVariant: colorScheme.onSurfaceVariant,
        tokens: tokens,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: colorScheme.brightness,
      canvasColor: colorScheme.surface,
      scaffoldBackgroundColor: colorScheme.surface,
      unselectedWidgetColor: colorScheme.onSurface,
      extensions: <ThemeExtension<dynamic>>[tokens],
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainer,
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(shape: buttonShape),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: buttonShape,
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(shape: buttonShape),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        collapsedShape: expansionTileShape,
        shape: expansionTileShape,
      ),
      iconTheme: IconThemeData(color: colorScheme.primary),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.primary,
        contentTextStyle: TextStyle(color: colorScheme.onPrimary),
      ),
      dividerTheme: DividerThemeData(
        color: tokens.borderSubtle,
        thickness: 1,
        space: 1,
      ),
      cardTheme: CardThemeData(
        color: tokens.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.cardRadius),
          side: BorderSide(color: tokens.border),
        ),
      ),
      textTheme: textTheme,
    );
  }

  /// Base roles mapped to [TenturaText] for dense operational screens.
  static TextTheme baseTextTheme({
    required Color onSurface,
    required Color onSurfaceVariant,
    required TenturaTokens tokens,
  }) {
    return TextTheme(
      displayMedium: const TextStyle(fontSize: 45),
      titleLarge: TenturaText.title(onSurface).copyWith(fontSize: 22),
      titleMedium: TenturaText.title(onSurface).copyWith(fontSize: 18),
      titleSmall: TenturaText.title(onSurface),
      headlineLarge: const TextStyle(fontSize: 22),
      headlineMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: onSurface,
      ),
      headlineSmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: onSurface,
      ),
      bodyLarge: TenturaText.body(onSurface).copyWith(fontSize: 16, height: 1.4),
      bodyMedium: TenturaText.body(onSurface).copyWith(fontSize: 14, height: 1.4),
      bodySmall: TenturaText.body(onSurface),
      labelLarge: TenturaText.command(onSurface),
      labelSmall: TenturaText.meta(onSurfaceVariant),
    ).apply(
      bodyColor: onSurface,
      displayColor: onSurface,
    );
  }
}
