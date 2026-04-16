/// Drift-backed settings (implemented by [SettingsRepository]).
abstract class SettingsRepositoryPort {
  Future<String?> getAppId();

  Future<void> setAppId(String value);

  Future<bool?> getIsIntroEnabled();

  Future<void> setIsIntroEnabled(bool value);

  Future<String?> getThemeModeName();

  Future<void> setThemeMode(String value);

  Future<int?> getNewStuffInboxLastSeenMs(String accountId);

  Future<void> setNewStuffInboxLastSeenMs(String accountId, int epochMs);

  Future<int?> getNewStuffMyWorkLastSeenMs(String accountId);

  Future<void> setNewStuffMyWorkLastSeenMs(String accountId, int epochMs);
}
