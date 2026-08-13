import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'users.dart';

class UserAvailability extends Table {
  late final userId = text().references(Users, #id)();

  late final isLimited = boolean().withDefault(const Constant(false))();

  late final resumeOn = customType(PgTypes.date).nullable()();

  late final updatedAt = customType(
    PgTypes.timestampWithTimezone,
  ).named('updated_at').clientDefault(() => PgDateTime(DateTime.timestamp()))();

  @override
  Set<Column> get primaryKey => {userId};

  @override
  String get tableName => 'user_availability';

  @override
  bool get withoutRowId => true;
}
