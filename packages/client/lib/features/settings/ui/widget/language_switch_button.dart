import 'package:get_it/get_it.dart';
import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/settings_cubit.dart';

class LanguageSwitchButton extends StatelessWidget {
  const LanguageSwitchButton({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return Semantics(
      label: l10n.labelLanguage,
      child: BlocSelector<SettingsCubit, SettingsState, String>(
        bloc: GetIt.I<SettingsCubit>(),
        selector: (state) => state.localePreference,
        builder: (_, localePreference) => SegmentedButton<String>(
          selected: <String>{localePreference},
          showSelectedIcon: false,
          segments: [
            ButtonSegment<String>(
              icon: const Icon(Icons.language_outlined),
              label: Text(l10n.languageSystem),
              tooltip: l10n.languageSystem,
              value: kLocalePreferenceSystem,
            ),
            ButtonSegment<String>(
              label: const Text('EN'),
              tooltip: l10n.english,
              value: kLocalePreferenceEn,
            ),
            ButtonSegment<String>(
              label: const Text('RU'),
              tooltip: l10n.russian,
              value: kLocalePreferenceRu,
            ),
          ],
          onSelectionChanged: (selected) => GetIt.I<SettingsCubit>()
              .setLocalePreference(selected.single),
        ),
      ),
    );
  }
}
