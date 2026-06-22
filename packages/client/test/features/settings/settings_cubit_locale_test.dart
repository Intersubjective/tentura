import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';

void main() {
  test('resolvedAppLocale maps explicit preferences', () {
    expect(
      const SettingsState(localePreference: kLocalePreferenceEn).resolvedAppLocale,
      const Locale('en'),
    );
    expect(
      const SettingsState(localePreference: kLocalePreferenceRu).resolvedAppLocale,
      const Locale('ru'),
    );
    expect(
      const SettingsState(localePreference: kLocalePreferenceSystem)
          .resolvedAppLocale,
      isNull,
    );
    expect(
      const SettingsState(localePreference: 'invalid').resolvedAppLocale,
      isNull,
    );
  });

  test('normalizeLocalePreference defaults and sanitizes stored values', () {
    expect(SettingsState.normalizeLocalePreference(null), kLocalePreferenceSystem);
    expect(
      SettingsState.normalizeLocalePreference(kLocalePreferenceEn),
      kLocalePreferenceEn,
    );
    expect(
      SettingsState.normalizeLocalePreference(kLocalePreferenceRu),
      kLocalePreferenceRu,
    );
    expect(
      SettingsState.normalizeLocalePreference('fr'),
      kLocalePreferenceSystem,
    );
  });
}
