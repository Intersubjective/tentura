import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'users.dart';

class PersonFieldFirstSeenInits extends Table {
  late final viewerId = text().references(
    Users,
    #id,
    onDelete: KeyAction.cascade,
  )();

  late final at = customType(
    PgTypes.timestampWithTimezone,
  ).withDefault(const CustomExpression('now()'))();

  late final backfillPending = boolean()();

  @override
  Set<Column<Object>> get primaryKey => {viewerId};

  @override
  String get tableName => 'person_field_first_seen_init';
}
