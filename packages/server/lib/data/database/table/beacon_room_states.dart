import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'beacon_blockers.dart';
import 'beacons.dart';
import 'users.dart';

class BeaconRoomStates extends Table {
  late final beaconId = text().references(Beacons, #id)();

  late final currentPlan = text().withDefault(const Constant(''))();

  late final openBlockerId =
      text().nullable().references(BeaconBlockers, #id)();

  late final lastRoomMeaningfulChange = text().nullable()();

  late final updatedAt = customType(
    PgTypes.timestampWithTimezone,
  ).clientDefault(() => PgDateTime(DateTime.timestamp()))();

  late final updatedBy = text().nullable().references(Users, #id)();

  @override
  Set<Column<Object>> get primaryKey => {beaconId};

  @override
  String get tableName => 'beacon_room_state';
}
