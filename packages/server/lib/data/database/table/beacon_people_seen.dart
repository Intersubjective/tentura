import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'beacons.dart';
import 'users.dart';

class BeaconPeopleSeen extends Table {
  late final userId =
      text().references(Users, #id, onDelete: KeyAction.cascade)();

  late final beaconId =
      text().references(Beacons, #id, onDelete: KeyAction.cascade)();

  late final lastSeenAt = customType(PgTypes.timestampWithTimezone)();

  @override
  Set<Column<Object>> get primaryKey => {userId, beaconId};

  @override
  String get tableName => 'beacon_people_seen';
}
