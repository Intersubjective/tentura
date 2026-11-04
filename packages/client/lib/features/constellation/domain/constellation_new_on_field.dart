import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/features/graph/domain/entity/node_details.dart';

/// Graph ids of people who are «new on your Field» and on the map (#898).
Set<GraphNodeId> constellationNewOnFieldGraphIds({
  required Map<GraphNodeId, NodeDetails> nodeByGraphId,
  required String viewerId,
  required bool Function(String personId) isNewOnField,
}) {
  final ids = <GraphNodeId>{};
  for (final MapEntry(key: graphId, value: node) in nodeByGraphId.entries) {
    if (node case FieldPersonNode(:final person)) {
      if (person.id != viewerId && isNewOnField(person.id)) {
        ids.add(graphId);
      }
    }
  }
  return ids;
}
