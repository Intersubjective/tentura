import 'package:get_it/get_it.dart';
import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/settings_cubit.dart';

class ThemeSwitchButton extends StatelessWidget {
  const ThemeSwitchButton({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return Semantics(
      label: l10n.labelTheme,
      child: BlocSelector<SettingsCubit, SettingsState, ThemeMode>(
        bloc: GetIt.I<SettingsCubit>(),
        selector: (state) => state.themeMode,
        // Same order and shape as the language control above it: System
        // first, every segment labelled. Three near-identical sun glyphs
        // (the dark one was a sun too) could not be told apart.
        builder: (_, themeMode) => SegmentedButton<ThemeMode>(
          selected: <ThemeMode>{themeMode},
          showSelectedIcon: false,
          segments: [
            ButtonSegment<ThemeMode>(
              icon: const Icon(Icons.brightness_auto_outlined),
              label: Text(l10n.system),
              tooltip: l10n.system,
              value: ThemeMode.system,
            ),
            ButtonSegment<ThemeMode>(
              icon: const Icon(Icons.light_mode_outlined),
              label: Text(l10n.light),
              tooltip: l10n.light,
              value: ThemeMode.light,
            ),
            ButtonSegment<ThemeMode>(
              icon: const Icon(Icons.dark_mode_outlined),
              label: Text(l10n.dark),
              tooltip: l10n.dark,
              value: ThemeMode.dark,
            ),
          ],
          onSelectionChanged: (selected) =>
              GetIt.I<SettingsCubit>().setThemeMode(selected.single),
        ),
      ),
    );
  }
}
