import 'package:flutter/material.dart';

import 'package:tentura/ui/bloc/state_base.dart';

export 'package:tentura/ui/bloc/state_base.dart';

part 'settings_state.freezed.dart';

const kLocalePreferenceSystem = 'system';
const kLocalePreferenceEn = 'en';
const kLocalePreferenceRu = 'ru';

const kSupportedLocalePreferences = {
  kLocalePreferenceSystem,
  kLocalePreferenceEn,
  kLocalePreferenceRu,
};

@freezed
abstract class SettingsState extends StateBase with _$SettingsState {
  const factory SettingsState({
    String? visibleVersion,
    @Default(kLocalePreferenceSystem) String localePreference,
    @Default(true) bool introEnabled,
    @Default(ThemeMode.system) ThemeMode themeMode,
    @Default(StateIsSuccess()) StateStatus status,
  }) = _SettingsState;

  const SettingsState._();

  static String normalizeLocalePreference(String? raw) {
    final value = raw ?? kLocalePreferenceSystem;
    return kSupportedLocalePreferences.contains(value)
        ? value
        : kLocalePreferenceSystem;
  }

  Locale? get resolvedAppLocale => switch (localePreference) {
    kLocalePreferenceEn => const Locale('en'),
    kLocalePreferenceRu => const Locale('ru'),
    _ => null,
  };
}
