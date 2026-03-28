import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/entity/beacon_update_entity.dart';

import 'beacons.dart';
import 'users.dart';

class BeaconUpdates extends Table {
  late final id = text().clientDefault(() => BeaconUpdateEntity.newId)();

  late final beaconId = text().references(Beacons, #id)();

  @ReferenceName('updateAuthor')
  late final authorId = text().references(Users, #id)();

  late final content = text().withLength(
    min: 1,
    max: kDescriptionMaxLength,
  )();

  late final createdAt = customType(
    PgTypes.timestampWithTimezone,
  ).clientDefault(() => PgDateTime(DateTime.timestamp()))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  String get tableName => 'beacon_update';

  @override
  bool get withoutRowId => true;
}
