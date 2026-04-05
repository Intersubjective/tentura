import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'beacons.dart';
import 'users.dart';

/// Private raw evaluation (submitter + server logic only).
class BeaconEvaluations extends Table {
  late final beaconId = text().references(Beacons, #id)();

  @ReferenceName('evaluationEvaluator')
  late final evaluatorId = text().references(Users, #id)();

  @ReferenceName('evaluationEvaluated')
  late final evaluatedUserId = text().references(Users, #id)();

  /// 0 NO_BASIS .. 5 POS_2
  late final Column<int> value = integer()();

  late final reasonTags = text().withDefault(const Constant(''))();

  late final note = text().withDefault(const Constant(''))();

  /// 0 draft, 1 submitted, 2 final, 3 responded (reserved)
  late final Column<int> status = integer().withDefault(const Constant(1))();

  late final createdAt = customType(
    PgTypes.timestampWithTimezone,
  ).clientDefault(() => PgDateTime(DateTime.timestamp()))();

  late final updatedAt = customType(
    PgTypes.timestampWithTimezone,
  ).clientDefault(() => PgDateTime(DateTime.timestamp()))();

  @override
  Set<Column<Object>> get primaryKey => {beaconId, evaluatorId, evaluatedUserId};

  @override
  String get tableName => 'beacon_evaluation';

  @override
  bool get withoutRowId => true;
}
