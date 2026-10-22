import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'beacons.dart';
import 'coordination_items.dart';
import 'users.dart';

class BeaconRoomStates extends Table {
  late final beaconId = text().references(Beacons, #id)();

  late final currentLine = text().withDefault(const Constant(''))();

  late final openBlockerId =
      text().nullable().references(CoordinationItems, #id)();

  late final lastRoomMeaningfulChange = text().nullable()();

  late final updatedAt = customType(
    PgTypes.timestampWithTimezone,
  ).clientDefault(() => PgDateTime(DateTime.timestamp()))();

  late final updatedBy = text().nullable().references(Users, #id)();

  /// Counts changes of [currentLine]; written by the
  /// `beacon_room_state_bump_line_revision` trigger only (m0259, #517).
  late final currentLineRevision = integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {beaconId};

  @override
  String get tableName => 'beacon_room_state';
}
