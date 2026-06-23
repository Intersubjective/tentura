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
        builder:
            (_, themeMode) => SegmentedButton<ThemeMode>(
              selected: <ThemeMode>{themeMode},
              showSelectedIcon: false,
              segments: [
                ButtonSegment<ThemeMode>(
                  icon: const Icon(Icons.brightness_7),
                  tooltip: l10n.light,
                  value: ThemeMode.light,
                ),
                ButtonSegment<ThemeMode>(
                  icon: const Icon(Icons.brightness_auto_outlined),
                  tooltip: l10n.system,
                  value: ThemeMode.system,
                ),
                ButtonSegment<ThemeMode>(
                  icon: const Icon(Icons.brightness_5),
                  tooltip: l10n.dark,
                  value: ThemeMode.dark,
                ),
              ],
              onSelectionChanged:
                  (selected) =>
                      GetIt.I<SettingsCubit>().setThemeMode(selected.single),
            ),
      ),
    );
  }
}
