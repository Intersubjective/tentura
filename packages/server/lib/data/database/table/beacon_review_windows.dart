import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'beacons.dart';

/// One row per beacon while / after a post-closure review window exists.
class BeaconReviewWindows extends Table {
  late final beaconId = text().references(Beacons, #id)();

  late final openedAt = customType(PgTypes.timestampWithTimezone)();

  late final closesAt = customType(PgTypes.timestampWithTimezone)();

  /// 0 = open, 1 = closed_complete
  late final Column<int> status = integer().withDefault(const Constant(0))();

  late final createdAt = customType(
    PgTypes.timestampWithTimezone,
  ).clientDefault(() => PgDateTime(DateTime.timestamp()))();

  late final updatedAt = customType(
    PgTypes.timestampWithTimezone,
  ).clientDefault(() => PgDateTime(DateTime.timestamp()))();

  @override
  Set<Column<Object>> get primaryKey => {beaconId};

  @override
  String get tableName => 'beacon_review_window';

  @override
  bool get withoutRowId => true;
}
