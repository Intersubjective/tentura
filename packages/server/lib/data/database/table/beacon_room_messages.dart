import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'beacon_blockers.dart';
import 'beacons.dart';
import 'pollings.dart';
import 'users.dart';

class BeaconRoomMessages extends Table {
  late final id = text()();

  late final beaconId = text().references(Beacons, #id)();

  late final authorId = text().references(Users, #id)();

  late final body = text().withDefault(const Constant(''))();

  late final replyToMessageId = text().nullable()();

  late final linkedBlockerId =
      text().nullable().references(BeaconBlockers, #id)();

  late final linkedNextMoveId = text().nullable()();

  late final linkedFactCardId = text().nullable()();

  late final linkedPollingId =
      text().nullable().references(Pollings, #id)();

  late final semanticMarker = integer().nullable()();

  late final systemPayload = customType(
    PgTypes.jsonb,
  ).nullable()();

  late final createdAt = customType(
    PgTypes.timestampWithTimezone,
  ).clientDefault(() => PgDateTime(DateTime.timestamp()))();

  late final editedAt = customType(
    PgTypes.timestampWithTimezone,
  ).nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  String get tableName => 'beacon_room_message';

  @override
  bool get withoutRowId => true;
}
