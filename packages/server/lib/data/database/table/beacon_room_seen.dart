import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'beacons.dart';
import 'coordination_items.dart';
import 'users.dart';

class BeaconRoomSeen extends Table {
  late final userId =
      text().references(Users, #id, onDelete: KeyAction.cascade)();

  late final beaconId =
      text().references(Beacons, #id, onDelete: KeyAction.cascade)();

  /// NULL = main room, non-null = item thread.
  late final threadItemId = text()
      .nullable()
      .references(CoordinationItems, #id, onDelete: KeyAction.cascade)();

  late final lastSeenAt = customType(PgTypes.timestampWithTimezone)();

  @override
  Set<Column<Object>> get primaryKey => {userId, beaconId, threadItemId};

  @override
  String get tableName => 'beacon_room_seen';

  @override
  bool get withoutRowId => true;
}
