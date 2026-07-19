import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'beacon_forward_edges.dart';

class ForwardDecisionAttributions extends Table {
  late final childForwardBatchId = text().named('child_forward_batch_id')();

  late final parentForwardEdgeId = text()
      .named('parent_forward_edge_id')
      .references(BeaconForwardEdges, #id)();

  late final attributionWeight = real().named('attribution_weight')();

  late final attributionMethod = text().named('attribution_method')();

  late final createdAt = customType(
    PgTypes.timestampWithTimezone,
  ).named('created_at').clientDefault(() => PgDateTime(DateTime.timestamp()))();

  @override
  Set<Column<Object>> get primaryKey => {
    childForwardBatchId,
    parentForwardEdgeId,
  };

  @override
  String get tableName => 'forward_decision_attribution';

  @override
  bool get withoutRowId => true;
}
