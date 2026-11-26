import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/phantom_pending_forward.dart';
import 'package:tentura_server/domain/port/owner_graph_transaction_port.dart';
import 'package:tentura_server/domain/port/phantom_pending_forward_repository_port.dart';

import '../database/tentura_db.dart';
import 'owner_graph_unit_of_work.dart';

@LazySingleton(as: PhantomPendingForwardRepositoryPort)
final class PhantomPendingForwardRepository
    implements PhantomPendingForwardRepositoryPort {
  const PhantomPendingForwardRepository(this._database);

  final TenturaDb _database;

  @override
  Future<bool> record(
    OwnerGraphScope scope, {
    required String id,
    required String phantomId,
    required String senderId,
    required String beaconId,
    required String? parentForwardEdgeId,
    required String note,
  }) async {
    requireOwnerGraphScope(_database, scope, senderId);
    final count = await _database.customUpdate(
      r'''
INSERT INTO public.phantom_pending_forward
  (id, phantom_id, sender_id, beacon_id, parent_forward_edge_id, note)
SELECT $1, id, owner_id, $4, $5, $6
FROM public.phantom
WHERE id = $2 AND owner_id = $3
ON CONFLICT (id) DO NOTHING
''',
      variables: [
        Variable.withString(id),
        Variable.withString(phantomId),
        Variable.withString(senderId),
        Variable.withString(beaconId),
        Variable<String>(parentForwardEdgeId),
        Variable.withString(note),
      ],
      updates: {_database.phantomPendingForwards},
      updateKind: UpdateKind.insert,
    );
    return count == 1;
  }

  @override
  Future<PhantomPendingForward?> findById({
    required String senderId,
    required String id,
  }) async {
    final row =
        await (_database.select(_database.phantomPendingForwards)..where(
              (row) => row.id.equals(id) & row.senderId.equals(senderId),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    return (
      id: row.id,
      phantomId: row.phantomId,
      senderId: row.senderId,
      beaconId: row.beaconId,
      parentForwardEdgeId: row.parentForwardEdgeId,
      note: row.note,
      createdAt: row.createdAt.dateTime,
      state: row.state,
      mergeId: row.mergeId,
      recipientId: row.recipientId,
      forwardEdgeId: row.forwardEdgeId,
      lapseReason: row.lapseReason,
      resolvedAt: row.resolvedAt?.dateTime,
    );
  }
}
