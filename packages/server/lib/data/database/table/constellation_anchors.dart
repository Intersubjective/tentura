import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'beacons.dart';
import 'users.dart';

/// Backed by `public.constellation_anchor` (see `m0167`).
class ConstellationAnchors extends Table {
  late final id = text()();

  late final viewerId = text().references(Users, #id)();

  late final personId = text().nullable().references(Users, #id)();

  late final beaconId = text().nullable().references(Beacons, #id)();

  late final xUnits = real()();

  late final yUnits = real()();

  late final coordinateSpaceVersion = integer()();

  late final revision = int64()();

  late final placedAt = customType(PgTypes.timestampWithTimezone)();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  String get tableName => 'constellation_anchor';

  @override
  bool get withoutRowId => true;
}
