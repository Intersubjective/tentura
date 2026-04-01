import 'package:drift/drift.dart';

import 'beacons.dart';
import 'users.dart';

/// Materialized participant rows for evaluation (author / committer / forwarder).
class BeaconEvaluationParticipants extends Table {
  late final beaconId = text().references(Beacons, #id)();

  @ReferenceName('evaluationParticipantUser')
  late final userId = text().references(Users, #id)();

  /// 0=author, 1=committer, 2=forwarder
  late final Column<int> role = integer()();

  late final contributionSummary = text()();

  late final causalHint = text()();

  @override
  Set<Column<Object>> get primaryKey => {beaconId, userId};

  @override
  String get tableName => 'beacon_evaluation_participant';

  @override
  bool get withoutRowId => true;
}
