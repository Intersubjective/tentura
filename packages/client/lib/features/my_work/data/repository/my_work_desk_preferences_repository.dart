import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura/data/database/database.dart';

import '../../domain/port/my_work_desk_preferences_port.dart';

@LazySingleton(
  as: MyWorkDeskPreferencesPort,
  env: [Environment.dev, Environment.prod],
)
class MyWorkDeskPreferencesRepository implements MyWorkDeskPreferencesPort {
  MyWorkDeskPreferencesRepository(this._database);

  final Database _database;

  @override
  Future<bool> isFinishedArchiveHintDismissed({required String userId}) =>
      _database.managers.settings
          .filter((f) => f.key.equals(_finishedArchiveHintDismissedKey(userId)))
          .getSingleOrNull()
          .then((v) => v?.valueBool ?? false);

  @override
  Future<void> setFinishedArchiveHintDismissed({required String userId}) =>
      _database.managers.settings.create(
        (o) => o(
          key: _finishedArchiveHintDismissedKey(userId),
          valueBool: const Value(true),
        ),
        mode: InsertMode.insertOrReplace,
        onConflict: DoUpdate(
          (_) => const SettingsCompanion(
            valueBool: Value(true),
          ),
        ),
      );

  static String _finishedArchiveHintDismissedKey(String userId) =>
      'myWork:finishedArchiveHintDismissed:$userId';
}
