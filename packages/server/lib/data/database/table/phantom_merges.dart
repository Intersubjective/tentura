import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'phantoms.dart';
import 'users.dart';

class PhantomMerges extends Table {
  late final id = text()();
  late final phantomId = text().references(
    Phantoms,
    #id,
    onDelete: KeyAction.cascade,
  )();

  @ReferenceName('ownedPhantomMerges')
  late final ownerId = text().references(
    Users,
    #id,
    onDelete: KeyAction.cascade,
  )();

  @ReferenceName('joinedPhantomMerges')
  late final userId = text().references(
    Users,
    #id,
    onDelete: KeyAction.cascade,
  )();

  late final origin = integer()();
  late final createdAt = customType(
    PgTypes.timestampWithTimezone,
  ).withDefault(const CustomExpression('now()'))();

  late final undo = customType(PgTypes.jsonb)();
  late final undoneAt = customType(PgTypes.timestampWithTimezone).nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  String get tableName => 'phantom_merge';
}
