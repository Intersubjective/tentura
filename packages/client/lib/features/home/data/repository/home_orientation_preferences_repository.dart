import 'package:injectable/injectable.dart';

import 'package:tentura/data/database/database.dart';

import '../../domain/entity/home_activation.dart';
import '../../domain/port/home_orientation_preferences_port.dart';

@LazySingleton(
  as: HomeOrientationPreferencesPort,
  env: [Environment.dev, Environment.prod],
)
class HomeOrientationPreferencesRepository
    implements HomeOrientationPreferencesPort {
  HomeOrientationPreferencesRepository(this._database);

  final Database _database;

  @override
  Future<bool> isActivated({required String userId}) =>
      _database.managers.settings
          .filter((f) => f.key.equals(_activatedKey(userId)))
          .getSingleOrNull()
          .then((v) => v?.valueBool ?? false);

  @override
  Future<void> setActivated({required String userId}) =>
      _database.managers.settings.create(
        (o) => o(
          key: _activatedKey(userId),
          valueBool: const Value(true),
        ),
        mode: InsertMode.insertOrReplace,
        onConflict: DoUpdate(
          (_) => const SettingsCompanion(
            valueBool: Value(true),
          ),
        ),
      );

  @override
  Future<bool> isOrientationDismissed({required String userId}) =>
      _database.managers.settings
          .filter((f) => f.key.equals(_orientationDismissedKey(userId)))
          .getSingleOrNull()
          .then((v) => v?.valueBool ?? false);

  @override
  Future<void> setOrientationDismissed({required String userId}) =>
      _database.managers.settings.create(
        (o) => o(
          key: _orientationDismissedKey(userId),
          valueBool: const Value(true),
        ),
        mode: InsertMode.insertOrReplace,
        onConflict: DoUpdate(
          (_) => const SettingsCompanion(
            valueBool: Value(true),
          ),
        ),
      );

  @override
  Future<void> resetFirstRunState({required String userId}) async {
    await _database.managers.settings
        .filter((f) => f.key.equals(_activatedKey(userId)))
        .delete();
    await _database.managers.settings
        .filter((f) => f.key.equals(_orientationDismissedKey(userId)))
        .delete();
  }

  @override
  Future<OrientationDebugOverride> getDebugOverride() =>
      _database.managers.settings
          .filter((f) => f.key.equals(_debugOverrideKey))
          .getSingleOrNull()
          .then((v) => _parseDebugOverride(v?.valueText));

  @override
  Future<void> setDebugOverride(OrientationDebugOverride value) =>
      _database.managers.settings.create(
        (o) => o(
          key: _debugOverrideKey,
          valueText: Value(value.name),
        ),
        mode: InsertMode.insertOrReplace,
        onConflict: DoUpdate(
          (_) => SettingsCompanion(
            valueText: Value(value.name),
          ),
        ),
      );

  static String _activatedKey(String userId) => 'home:activated:$userId';

  static String _orientationDismissedKey(String userId) =>
      'home:orientationDismissed:$userId';

  static const _debugOverrideKey = 'home:orientationDebugOverride';

  static OrientationDebugOverride _parseDebugOverride(String? raw) {
    if (raw == null || raw.isEmpty) {
      return OrientationDebugOverride.auto;
    }
    for (final override in OrientationDebugOverride.values) {
      if (override.name == raw) {
        return override;
      }
    }
    return OrientationDebugOverride.auto;
  }
}
