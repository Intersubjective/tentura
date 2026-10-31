import 'package:tentura/features/settings/ui/bloc/settings_state.dart';

const kLandingLangQueryParam = 'lang';

/// Supported `?lang=` values the landing may hand off to the app.
String? normalizeLandingLangQuery(String? raw) {
  switch (raw?.trim().toLowerCase()) {
    case kLocalePreferenceRu:
      return kLocalePreferenceRu;
    case kLocalePreferenceEn:
      return kLocalePreferenceEn;
    default:
      return null;
  }
}

/// Whether a stored settings value is an explicit in-app language choice.
bool storedLocalePreferenceBlocksLandingHandoff(String? storedRaw) {
  final stored = storedRaw ?? kLocalePreferenceSystem;
  return stored == kLocalePreferenceEn || stored == kLocalePreferenceRu;
}

/// Maps a landing hand-off query to the persisted settings preference, if any.
String? landingLangQueryToLocalePreference(String? landingLangQuery) {
  final normalized = normalizeLandingLangQuery(landingLangQuery);
  if (normalized == null) {
    return null;
  }
  return normalized;
}

/// Resolves the locale preference after optional landing hand-off.
String resolveLocalePreferenceAfterLandingHandoff({
  required String? storedRaw,
  required String? landingLangQuery,
}) {
  final stored = SettingsState.normalizeLocalePreference(storedRaw);
  if (storedLocalePreferenceBlocksLandingHandoff(storedRaw)) {
    return stored;
  }
  final fromLanding = landingLangQueryToLocalePreference(landingLangQuery);
  if (fromLanding != null) {
    return fromLanding;
  }
  return stored;
}
