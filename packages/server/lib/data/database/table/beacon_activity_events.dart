import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_server/domain/entity/beacon_activity_event_entity.dart';

import 'beacons.dart';
import 'users.dart';

/// Backed by `public.beacon_activity_event` (see `m0040`).
class BeaconActivityEvents extends Table {
  late final id =
      text().clientDefault(() => BeaconActivityEventEntity.newId)();

  late final beaconId = text().references(Beacons, #id)();

  late final Column<int> visibility = integer()();

  late final Column<int> type = integer()();

  late final actorId = text().nullable().references(Users, #id)();

  late final targetUserId = text().nullable().references(Users, #id)();

  late final sourceMessageId = text().nullable()();

  late final diff = customType(PgTypes.jsonb).nullable()();

  late final createdAt = customType(
    PgTypes.timestampWithTimezone,
  ).clientDefault(() => PgDateTime(DateTime.timestamp()))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  String get tableName => 'beacon_activity_event';

  @override
  bool get withoutRowId => true;
}
