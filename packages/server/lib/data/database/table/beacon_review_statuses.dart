import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'beacons.dart';
import 'users.dart';

/// Per-user review workflow status for a beacon.
class BeaconReviewStatuses extends Table {
  late final beaconId = text().references(Beacons, #id)();

  @ReferenceName('reviewStatusUser')
  late final userId = text().references(Users, #id)();

  /// 0 not_started, 1 in_progress, 2 submitted, 3 skipped, 4 expired
  late final Column<int> status = integer().withDefault(const Constant(0))();

  late final createdAt = customType(
    PgTypes.timestampWithTimezone,
  ).clientDefault(() => PgDateTime(DateTime.timestamp()))();

  late final updatedAt = customType(
    PgTypes.timestampWithTimezone,
  ).clientDefault(() => PgDateTime(DateTime.timestamp()))();

  @override
  Set<Column<Object>> get primaryKey => {beaconId, userId};

  @override
  String get tableName => 'beacon_review_status';

  @override
  bool get withoutRowId => true;
}
