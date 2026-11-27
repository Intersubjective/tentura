import 'package:tentura_server/domain/coordination/resolve_forward_parent_edge.dart';

import '../database/tentura_db.dart';

/// Locks each hop inside the caller's transaction until the forward commits.
Future<bool> lockActiveForwardParentChain(
  TenturaDb database,
  String? parentEdgeId,
) => hasLiveForwardParentChain(
  parentEdgeId,
  readEdge: (edgeId) async {
    final edge = await database
        .customSelect(
          'SELECT parent_edge_id, cancelled_at IS NULL AS active '
          r'FROM public.beacon_forward_edge WHERE id = $1 FOR UPDATE',
          variables: [Variable.withString(edgeId)],
        )
        .getSingleOrNull();
    return edge == null
        ? null
        : (
            parentEdgeId: edge.readNullable<String>('parent_edge_id'),
            active: edge.read<bool>('active'),
          );
  },
);
