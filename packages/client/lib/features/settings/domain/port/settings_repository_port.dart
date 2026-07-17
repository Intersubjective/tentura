import 'package:tentura/features/notification/domain/entity/last_fcm_registration.dart';
import 'package:tentura/features/settings/data/repository/settings_repository.dart'
    show SettingsRepository;

/// Drift-backed settings (implemented by [SettingsRepository]).
abstract class SettingsRepositoryPort {
  Future<String?> getAppId();

  Future<void> setAppId(String value);

  Future<LastFcmRegistration?> getLastFcmRegistration();

  Future<void> setLastFcmRegistration(LastFcmRegistration? value);

  Future<bool?> getIsIntroEnabled();

  Future<void> setIsIntroEnabled(bool value);

  Future<String?> getThemeModeName();

  Future<void> setThemeMode(String value);

  Future<String?> getLocalePreference();

  Future<void> setLocalePreference(String value);
}
