import 'dart:convert';

import 'package:injectable/injectable.dart';

import 'package:tentura/data/database/database.dart';
import 'package:tentura/features/notification/domain/entity/last_fcm_registration.dart';

import '../../domain/port/settings_repository_port.dart';

@Singleton(
  as: SettingsRepositoryPort,
  env: [Environment.dev, Environment.prod],
)
class SettingsRepository implements SettingsRepositoryPort {
  SettingsRepository(this._database);

  final Database _database;

  ///
  /// Application Id for instance
  ///
  @override
  Future<String?> getAppId() => _database.managers.settings
      .filter((f) => f.key.equals(_kAppIdKey))
      .getSingleOrNull()
      .then((v) => v?.valueText);

  //
  //
  @override
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

  @override
  Future<LastFcmRegistration?> getLastFcmRegistration() async {
    final raw = await _database.managers.settings
        .filter((f) => f.key.equals(_kLastFcmRegistrationKey))
        .getSingleOrNull()
        .then((v) => v?.valueText);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return LastFcmRegistration(
      accountId: map['accountId']! as String,
      appId: map['appId']! as String,
      token: map['token']! as String,
    );
  }

  @override
  Future<void> setLastFcmRegistration(LastFcmRegistration? value) async {
    if (value == null) {
      await _database.managers.settings
          .filter((f) => f.key.equals(_kLastFcmRegistrationKey))
          .delete();
      return;
    }
    final encoded = jsonEncode({
      'accountId': value.accountId,
      'appId': value.appId,
      'token': value.token,
    });
    await _database.managers.settings.create(
      (o) => o(
        key: _kLastFcmRegistrationKey,
        valueText: Value(encoded),
      ),
      mode: InsertMode.insertOrReplace,
      onConflict: DoUpdate(
        (_) => SettingsCompanion(
          valueText: Value(encoded),
        ),
      ),
    );
  }

  ///
  /// Intro
  ///
  @override
  Future<bool?> getIsIntroEnabled() => _database.managers.settings
      .filter((f) => f.key.equals(_kIsIntroEnabledKey))
      .getSingleOrNull()
      .then((v) => v?.valueBool);

  //
  //
  @override
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
  @override
  Future<String?> getThemeModeName() => _database.managers.settings
      .filter((f) => f.key.equals(_kThemeModeKey))
      .getSingleOrNull()
      .then((v) => v?.valueText);

  //
  //
  @override
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

  ///
  /// Locale
  ///
  @override
  Future<String?> getLocalePreference() => _database.managers.settings
      .filter((f) => f.key.equals(_kLocalePreferenceKey))
      .getSingleOrNull()
      .then((v) => v?.valueText);

  //
  //
  @override
  Future<void> setLocalePreference(String value) =>
      _database.managers.settings.create(
        (o) => o(
          key: _kLocalePreferenceKey,
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
  @override
  Future<int?> getNewStuffInboxLastSeenMs(String accountId) =>
      _database.managers.settings
          .filter((f) => f.key.equals(_newStuffInboxKey(accountId)))
          .getSingleOrNull()
          .then((v) => v?.valueInt);

  @override
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
  @override
  Future<int?> getNewStuffMyWorkLastSeenMs(String accountId) =>
      _database.managers.settings
          .filter((f) => f.key.equals(_newStuffMyWorkKey(accountId)))
          .getSingleOrNull()
          .then((v) => v?.valueInt);

  @override
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
  static const _kLastFcmRegistrationKey = 'lastFcmRegistration';
  static const _kThemeModeKey = 'themeMode';
  static const _kLocalePreferenceKey = 'localePreference';
  static const _kIsIntroEnabledKey = 'isIntroEnabled';
}
