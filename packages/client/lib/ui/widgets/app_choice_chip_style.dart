import 'package:flutter/material.dart';

/// Shared `ChoiceChip` colors for screens like My Work and Inbox.
///
/// Light: selected fill uses `ColorScheme.primary` with `onPrimary` because the
/// generated secondary-container pair is too low-contrast for this palette.
///
/// Dark: selected fill keeps secondary-container tones.
class AppChoiceChipStyle {
  AppChoiceChipStyle(this.scheme);

  final ColorScheme scheme;

  bool get _light => scheme.brightness == Brightness.light;

  Color get _selectedFill => _light ? scheme.primary : scheme.secondaryContainer;

  Color get _selectedOnFill =>
      _light ? scheme.onPrimary : scheme.onSecondaryContainer;

  WidgetStateProperty<Color?> get background =>
      WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return _selectedFill;
        }
        if (states.contains(WidgetState.disabled)) {
          return scheme.surfaceContainerHighest.withValues(alpha: 0.5);
        }
        return scheme.surfaceContainerHighest;
      });

  WidgetStateColor get labelForeground =>
      WidgetStateColor.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return _selectedOnFill;
        }
        if (states.contains(WidgetState.disabled)) {
          return scheme.onSurface.withValues(alpha: 0.38);
        }
        return scheme.onSurface;
      });

  WidgetStateBorderSide get outline => WidgetStateBorderSide.resolveWith((
        states,
      ) {
        if (states.contains(WidgetState.selected)) {
          return BorderSide.none;
        }
        return BorderSide(color: scheme.outlineVariant);
      });

  Color get checkmarkColor => _selectedOnFill;

  /// Optional count suffix on section chips: secondary label when unselected;
  /// slightly muted selected foreground on the selected fill.
  Color counterForeground({required bool chipSelected}) {
    if (!chipSelected) {
      return scheme.onSurfaceVariant;
    }
    return _selectedOnFill.withValues(alpha: 0.92);
  }
}
