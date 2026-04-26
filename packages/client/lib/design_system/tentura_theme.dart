import 'package:flutter/material.dart';

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
    final textTheme = baseTextTheme(
      onSurface: onSurface,
      onSurfaceVariant: colorScheme.onSurfaceVariant,
    );

    final isDark = colorScheme.brightness == Brightness.dark;
    final navIndicatorColor = isDark
        ? colorScheme.secondaryContainer
        : colorScheme.primary;
    final navSelectedIconColor = isDark
        ? colorScheme.onSecondaryContainer
        : colorScheme.onPrimary;

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
      navigationBarTheme: NavigationBarThemeData(
        height: tokens.bottomNavHeight,
        backgroundColor: colorScheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        indicatorColor: navIndicatorColor,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return IconThemeData(
              size: 24,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.38),
            );
          }
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(
              size: 24,
              color: navSelectedIconColor,
            );
          }
          return IconThemeData(
            size: 24,
            color: colorScheme.onSurfaceVariant,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final disabled = states.contains(WidgetState.disabled);
          final selected = states.contains(WidgetState.selected);

          final color = disabled
              ? colorScheme.onSurfaceVariant.withValues(alpha: 0.38)
              : selected
                  ? colorScheme.onSurface
                  : colorScheme.onSurfaceVariant;

          return TenturaText.navLabel(color).copyWith(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          );
        }),
      ),
      textTheme: textTheme,
    );
  }

  /// Base roles mapped to [TenturaText] for dense operational screens (Inter).
  static TextTheme baseTextTheme({
    required Color onSurface,
    required Color onSurfaceVariant,
  }) {
    return TextTheme(
      displayLarge: TenturaText.displayLarge(onSurface),
      displayMedium: TenturaText.displayMedium(onSurface),
      displaySmall: TenturaText.displaySmall(onSurface),
      headlineLarge: TenturaText.headlineLarge(onSurface),
      headlineMedium: TenturaText.headlineMedium(onSurface),
      headlineSmall: TenturaText.headlineSmall(onSurface),
      titleLarge: TenturaText.titleLarge(onSurface),
      titleMedium: TenturaText.title(onSurface),
      titleSmall: TenturaText.titleSmall(onSurface),
      bodyLarge: TenturaText.bodyLarge(onSurface),
      bodyMedium: TenturaText.bodyMedium(onSurface),
      bodySmall: TenturaText.bodySmall(onSurface),
      labelLarge: TenturaText.labelLarge(onSurface),
      labelMedium: TenturaText.labelMedium(onSurface),
      labelSmall: TenturaText.labelSmall(onSurfaceVariant),
    ).apply(
      bodyColor: onSurface,
      displayColor: onSurface,
    );
  }
}
