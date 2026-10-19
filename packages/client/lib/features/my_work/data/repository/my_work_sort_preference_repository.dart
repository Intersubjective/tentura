import 'package:injectable/injectable.dart';

import 'package:tentura/data/database/database.dart';

import '../../domain/entity/my_work_sort.dart';
import '../../domain/port/my_work_sort_preference_port.dart';

@LazySingleton(
  as: MyWorkSortPreferencePort,
  env: [Environment.dev, Environment.prod],
)
class MyWorkSortPreferenceRepository implements MyWorkSortPreferencePort {
  MyWorkSortPreferenceRepository(this._database);

  final Database _database;

  @override
  Future<MyWorkSort?> getSort() => _database.managers.settings
      .filter((f) => f.key.equals(_sortKey))
      .getSingleOrNull()
      .then((v) => _parseSort(v?.valueText));

  @override
  Future<void> setSort(MyWorkSort sort) => _database.managers.settings.create(
    (o) => o(
      key: _sortKey,
      valueText: Value(sort.name),
    ),
    mode: InsertMode.insertOrReplace,
    onConflict: DoUpdate(
      (_) => SettingsCompanion(
        valueText: Value(sort.name),
      ),
    ),
  );

  /// Device-level (not per user): the issue asks for the order per device.
  static const _sortKey = 'myWork:sort';

  static MyWorkSort? _parseSort(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    for (final sort in MyWorkSort.values) {
      if (sort.name == raw) {
        return sort;
      }
    }
    return null;
  }
}
