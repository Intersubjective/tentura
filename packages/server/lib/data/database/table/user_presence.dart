import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_root/domain/enums.dart';

import 'users.dart';

class UserPresence extends Table {
  late final userId = text().references(Users, #id)();

  late final lastSeenAt = customType(
    PgTypes.timestampWithTimezone,
  ).clientDefault(() => PgDateTime(DateTime.timestamp()))();

  late final lastNotifiedAt = customType(
    PgTypes.timestampWithTimezone,
  ).clientDefault(() => PgDateTime(DateTime.timestamp()))();

  late final status = intEnum<UserPresenceStatus>().clientDefault(() => 0)();

  @override
  Set<Column> get primaryKey => {userId};

  @override
  String get tableName => 'user_presence';

  @override
  bool get withoutRowId => true;
}
