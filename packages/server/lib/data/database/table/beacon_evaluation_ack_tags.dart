import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'beacons.dart';
import 'users.dart';

class BeaconEvaluationAckTags extends Table {
  late final beaconId = text().references(Beacons, #id)();

  @ReferenceName('ackTagEvaluator')
  late final evaluatorId = text().references(Users, #id)();

  @ReferenceName('ackTagSubject')
  late final subjectId = text().references(Users, #id)();

  late final tagSlug = text()();

  late final createdAt = customType(
    PgTypes.timestampWithTimezone,
  ).named('created_at').clientDefault(() => PgDateTime(DateTime.timestamp()))();

  @override
  Set<Column<Object>> get primaryKey =>
      {beaconId, evaluatorId, subjectId, tagSlug};

  @override
  String get tableName => 'beacon_evaluation_ack_tag';

  @override
  bool get withoutRowId => true;
}
