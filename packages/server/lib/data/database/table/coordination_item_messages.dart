import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'beacons.dart';
import 'coordination_items.dart';
import 'users.dart';

class CoordinationItemMessages extends Table {
  late final id = text()();
  late final itemId = text().references(CoordinationItems, #id)();
  late final beaconId = text().references(Beacons, #id)();
  late final senderId = text().references(Users, #id)();
  late final body = text().withDefault(const Constant(''))();
  late final createdAt = customType(PgTypes.timestampWithTimezone).clientDefault(() => PgDateTime(DateTime.timestamp()))();
  late final editedAt = customType(PgTypes.timestampWithTimezone).nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  String get tableName => 'coordination_item_message';

  @override
  bool get withoutRowId => true;
}
