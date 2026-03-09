import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_root/domain/enums.dart';

import 'users.dart';

class Complaints extends Table {
  late final id = text()();

  late final userId = text().references(Users, #id)();

  late final email = text()();

  late final details = text()();

  late final type = intEnum<ComplaintType>().clientDefault(() => 0)();

  late final createdAt = customType(
    PgTypes.timestampWithTimezone,
  ).clientDefault(() => PgDateTime(DateTime.timestamp()))();

  @override
  Set<Column<Object>> get primaryKey => {id, userId};

  @override
  String get tableName => 'complaint';

  @override
  bool get withoutRowId => true;
}
