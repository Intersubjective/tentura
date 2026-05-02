import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'beacons.dart';
import 'users.dart';

class PersonCapabilityEvents extends Table {
  late final id = text()();

  @ReferenceName('capabilitySubject')
  late final subjectUserId = text().references(Users, #id)();

  @ReferenceName('capabilityObserver')
  late final observerUserId = text().references(Users, #id)();

  late final tagSlug = text()();

  late final sourceType = integer()();

  @ReferenceName('capabilityBeacon')
  late final beaconId = text().nullable().references(Beacons, #id)();

  late final visibility = integer().withDefault(const Constant(0))();

  late final note = text().withDefault(const Constant(''))();

  late final createdAt = customType(
    PgTypes.timestampWithTimezone,
  ).clientDefault(() => PgDateTime(DateTime.timestamp()))();

  late final deletedAt = customType(PgTypes.timestampWithTimezone).nullable()();

  late final isNegative = boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  String get tableName => 'person_capability_event';

  @override
  bool get withoutRowId => true;
}
