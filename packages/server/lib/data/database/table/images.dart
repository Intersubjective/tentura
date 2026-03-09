import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'users.dart';

class Images extends Table {
  late final id = customType(PgTypes.uuid).withDefault(genRandomUuid())();

  @ReferenceName('author')
  late final authorId = text().references(Users, #id)();

  late final Column<int> height = integer()
      .check(height.isBiggerOrEqualValue(0))
      .clientDefault(() => 0)();

  late final Column<int> width = integer()
      .check(width.isBiggerOrEqualValue(0))
      .clientDefault(() => 0)();

  late final hash = text().clientDefault(() => '')();

  late final createdAt = customType(
    PgTypes.timestampWithTimezone,
  ).clientDefault(() => PgDateTime(DateTime.timestamp()))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  String get tableName => 'image';

  @override
  bool get withoutRowId => true;
}
