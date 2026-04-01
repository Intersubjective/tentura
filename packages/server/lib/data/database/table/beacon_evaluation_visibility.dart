import 'package:drift/drift.dart';

import 'beacons.dart';
import 'users.dart';

/// Which evaluator may see which participant card (Phase 1 rules).
class BeaconEvaluationVisibility extends Table {
  late final beaconId = text().references(Beacons, #id)();

  @ReferenceName('visibilityEvaluator')
  late final evaluatorId = text().references(Users, #id)();

  @ReferenceName('visibilityParticipant')
  late final participantId = text().references(Users, #id)();

  @override
  Set<Column<Object>> get primaryKey => {beaconId, evaluatorId, participantId};

  @override
  String get tableName => 'beacon_evaluation_visibility';

  @override
  bool get withoutRowId => true;
}
