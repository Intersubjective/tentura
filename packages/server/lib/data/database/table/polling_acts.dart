import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'polling_variants.dart';
import 'pollings.dart';
import 'users.dart';

class PollingActs extends Table {
  late final authorId = text().references(Users, #id)();

  late final pollingId = text().references(Pollings, #id)();

  late final pollingVariantId = text().references(PollingVariants, #id)();

  late final score = integer().nullable()();

  late final createdAt = customType(
    PgTypes.timestampWithTimezone,
  ).clientDefault(() => PgDateTime(DateTime.timestamp()))();

  @override
  Set<Column<Object>> get primaryKey => {authorId, pollingVariantId};

  @override
  String get tableName => 'polling_act';

  @override
  bool get withoutRowId => true;
}
