import 'package:drift/drift.dart';

import 'beacons.dart';
import 'users.dart';

/// At most one Beacon Steward per beacon (`beacon_id` primary key).
class BeaconStewards extends Table {
  late final beaconId = text().references(Beacons, #id)();

  late final userId = text().references(Users, #id)();

  @override
  Set<Column<Object>> get primaryKey => {beaconId};

  @override
  String get tableName => 'beacon_steward';
}
