import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'utils/ui_utils.dart';

const colorSchemeLight = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF014F86),
  onPrimary: Color(0xFFE5E7EB),
  secondary: Color(0xFF6CBCE3),
  onSecondary: Color(0xFFE1E1E1),
  error: Color(0xFFD14343),
  onError: Colors.white,
  surface: Color(0xFFF4F4F4),
  surfaceContainer: Colors.white,
  onSurface: Color(0xFF1A1A1A),
  onSurfaceVariant: Color(0xFF4B5563),
  outlineVariant: Color(0xFF4B5563),
  primaryFixed: Color(0xFF014F86),
);

const colorSchemeDark = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFF6CBCE3),
  onPrimary: Color(0xFF0A1826),
  secondary: Color(0xFF014F86),
  onSecondary: Color(0xFFE1E1E1),
  error: Color(0xFFD14343),
  onError: Colors.white,
  surface: Color(0xFF0A1826),
  surfaceContainer: Color(0xFF1D2935),
  onSurface: Color(0xFFE1E1E1),
  onSurfaceVariant: Color(0xFFE5E7EB),
  outlineVariant: Color(0xFF444746),
  primaryFixed: Color(0xFF014F86),
);

ThemeData createAppTheme(ColorScheme colorScheme) {
  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(kBorderRadius),
  );

  final expansionTileShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(kBorderRadius),
    side: BorderSide(color: colorScheme.outline),
  );

  return ThemeData(
    colorScheme: colorScheme,
    brightness: colorScheme.brightness,
    canvasColor: colorScheme.surfaceTint,
    scaffoldBackgroundColor: colorScheme.surface,
    unselectedWidgetColor: colorScheme.onSurface,

    // Dialog
    dialogTheme: DialogThemeData(
      backgroundColor: colorScheme.surfaceContainer,
    ),

    // DropdownMenu
    dropdownMenuTheme: const DropdownMenuThemeData(
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    ),

    // Elevated Button
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(shape: buttonShape),
    ),

    // Outlined Button
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: buttonShape,
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
    ),

    expansionTileTheme: ExpansionTileThemeData(
      collapsedShape: expansionTileShape,
      shape: expansionTileShape,
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: ElevatedButton.styleFrom(shape: buttonShape),
    ),

    // Icon
    iconTheme: IconThemeData(color: colorScheme.primary),

    //Snack Bar
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colorScheme.primary,
      contentTextStyle: TextStyle(color: colorScheme.onPrimary),
    ),

    //Text
    textTheme: GoogleFonts.robotoTextTheme()
        .copyWith(
          displayMedium: const TextStyle(fontSize: 45),
          titleLarge: const TextStyle(fontSize: 22),
          titleMedium: const TextStyle(fontSize: 18),
          titleSmall: const TextStyle(fontSize: 14),
          headlineLarge: const TextStyle(fontSize: 22),
          headlineMedium: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          headlineSmall: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          bodyLarge: const TextStyle(fontSize: 16),
          bodyMedium: const TextStyle(fontSize: 14),
          bodySmall: const TextStyle(fontSize: 12),
        )
        .apply(
          bodyColor: colorScheme.onSurface,
          displayColor: colorScheme.onSurface,
        ),

    //
    chipTheme: ChipThemeData(
      labelStyle: TextStyle(color: colorScheme.onPrimary),
      backgroundColor: colorScheme.primary,
    ),
  );
}
