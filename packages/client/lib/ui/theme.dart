import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_theme.dart';

/// Application [ThemeData]. Delegates to [TenturaTheme]; the [ColorScheme]
/// argument selects light vs dark (compatibility with existing call sites).
ThemeData createAppTheme(ColorScheme colorScheme) =>
    colorScheme.brightness == Brightness.dark
    ? TenturaTheme.dark()
    : TenturaTheme.light();

/// Light [ColorScheme] from the current design system (for previews/tests).
ColorScheme get colorSchemeLight => TenturaTheme.light().colorScheme;

/// Dark [ColorScheme] from the current design system (for previews/tests).
ColorScheme get colorSchemeDark => TenturaTheme.dark().colorScheme;
