import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'beacons.dart';
import 'users.dart';

class CoordinationItems extends Table {
  late final id = text()();
  late final beaconId = text().references(Beacons, #id)();
  late final Column<int> kind = integer()();
  late final Column<int> status = integer().withDefault(const Constant(0))();
  late final title = text().withDefault(const Constant(''))();
  late final body = text().withDefault(const Constant(''))();
  late final creatorId = text().references(Users, #id)();
  late final targetPersonId = text().nullable().references(Users, #id)();
  late final acceptedById = text().nullable().references(Users, #id)();
  late final targetItemId = text().nullable()();
  late final targetMessageId = text().nullable()();
  late final linkedMessageId = text().nullable()();
  late final linkedParentItemId = text().nullable()();
  late final Column<int> ordering = integer().withDefault(const Constant(0))();
  late final createdAt = customType(PgTypes.timestampWithTimezone).clientDefault(() => PgDateTime(DateTime.timestamp()))();
  late final updatedAt = customType(PgTypes.timestampWithTimezone).clientDefault(() => PgDateTime(DateTime.timestamp()))();
  late final resolvedAt = customType(PgTypes.timestampWithTimezone).nullable()();
  late final cancelledAt = customType(PgTypes.timestampWithTimezone).nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  String get tableName => 'coordination_item';

  @override
  bool get withoutRowId => true;
}
