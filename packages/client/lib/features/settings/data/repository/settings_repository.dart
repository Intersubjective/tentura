import 'package:injectable/injectable.dart';

import 'package:tentura/data/database/database.dart';

@singleton
class SettingsRepository {
  SettingsRepository(this._database);

  final Database _database;

  ///
  /// Application Id for instance
  ///
  Future<String?> getAppId() => _database.managers.settings
      .filter((f) => f.key.equals(_kAppIdKey))
      .getSingleOrNull()
      .then((v) => v?.valueText);

  //
  //
  Future<void> setAppId(String value) => _database.managers.settings.create(
    (o) => o(
      key: _kAppIdKey,
      valueText: Value(value),
    ),
    mode: InsertMode.insertOrReplace,
    onConflict: DoUpdate(
      (_) => SettingsCompanion(
        valueText: Value(value),
      ),
    ),
  );

  ///
  /// Intro
  ///
  Future<bool?> getIsIntroEnabled() => _database.managers.settings
      .filter((f) => f.key.equals(_kIsIntroEnabledKey))
      .getSingleOrNull()
      .then((v) => v?.valueBool);

  //
  //
  Future<void> setIsIntroEnabled(bool value) =>
      _database.managers.settings.create(
        (o) => o(
          key: _kIsIntroEnabledKey,
          valueBool: Value(value),
        ),
        mode: InsertMode.insertOrReplace,
        onConflict: DoUpdate(
          (_) => SettingsCompanion(
            valueBool: Value(value),
          ),
        ),
      );

  ///
  /// Theme
  ///
  Future<String?> getThemeModeName() => _database.managers.settings
      .filter((f) => f.key.equals(_kThemeModeKey))
      .getSingleOrNull()
      .then((v) => v?.valueText);

  //
  //
  Future<void> setThemeMode(String value) => _database.managers.settings.create(
    (o) => o(
      key: _kThemeModeKey,
      valueText: Value(value),
    ),
    mode: InsertMode.insertOrReplace,
    onConflict: DoUpdate(
      (_) => SettingsCompanion(
        valueText: Value(value),
      ),
    ),
  );

  // Keys
  /// Last-seen cursor for Inbox "new stuff" (epoch ms, server-aligned via max forward timestamps).
  Future<int?> getNewStuffInboxLastSeenMs(String accountId) =>
      _database.managers.settings
          .filter((f) => f.key.equals(_newStuffInboxKey(accountId)))
          .getSingleOrNull()
          .then((v) => v?.valueInt);

  Future<void> setNewStuffInboxLastSeenMs(String accountId, int epochMs) =>
      _database.managers.settings.create(
        (o) => o(
          key: _newStuffInboxKey(accountId),
          valueInt: Value(epochMs),
        ),
        mode: InsertMode.insertOrReplace,
        onConflict: DoUpdate(
          (_) => SettingsCompanion(
            valueInt: Value(epochMs),
          ),
        ),
      );

  /// Last-seen cursor for My Work "new stuff" (epoch ms).
  Future<int?> getNewStuffMyWorkLastSeenMs(String accountId) =>
      _database.managers.settings
          .filter((f) => f.key.equals(_newStuffMyWorkKey(accountId)))
          .getSingleOrNull()
          .then((v) => v?.valueInt);

  Future<void> setNewStuffMyWorkLastSeenMs(String accountId, int epochMs) =>
      _database.managers.settings.create(
        (o) => o(
          key: _newStuffMyWorkKey(accountId),
          valueInt: Value(epochMs),
        ),
        mode: InsertMode.insertOrReplace,
        onConflict: DoUpdate(
          (_) => SettingsCompanion(
            valueInt: Value(epochMs),
          ),
        ),
      );

  /// Keys for `newStuff` indicators (per account).
  static String _newStuffInboxKey(String accountId) => 'newStuff:inbox:$accountId';

  static String _newStuffMyWorkKey(String accountId) => 'newStuff:myWork:$accountId';

  static const _kAppIdKey = 'appId';
  static const _kThemeModeKey = 'themeMode';
  static const _kIsIntroEnabledKey = 'isIntroEnabled';
}
