import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'users.dart';

class FcmTokens extends Table {
  late final userId = text().references(Users, #id)();

  late final appId = customType(PgTypes.uuid)();

  late final token = text()();

  late final platform = text()();

  late final createdAt = customType(
    PgTypes.timestampWithTimezone,
  ).clientDefault(() => PgDateTime(DateTime.timestamp()))();

  @override
  Set<Column<Object>> get primaryKey => {userId, appId};

  @override
  String get tableName => 'fcm_token';

  @override
  bool get withoutRowId => true;
}
