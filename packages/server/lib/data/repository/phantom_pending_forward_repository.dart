import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/phantom_pending_forward.dart';
import 'package:tentura_server/domain/port/owner_graph_transaction_port.dart';
import 'package:tentura_server/domain/port/phantom_pending_forward_repository_port.dart';

import '../database/tentura_db.dart';
import 'forward_parent_chain_lock.dart';
import 'owner_graph_unit_of_work.dart';

@LazySingleton(as: PhantomPendingForwardRepositoryPort)
final class PhantomPendingForwardRepository
    implements PhantomPendingForwardRepositoryPort {
  const PhantomPendingForwardRepository(this._database);

  final TenturaDb _database;

  @override
  Future<bool> hasPending({
    required String phantomId,
    required String senderId,
    required String beaconId,
  }) => _database.managers.phantomPendingForwards
      .filter(
        (row) =>
            row.phantomId.id(phantomId) &
            row.senderId.id(senderId) &
            row.beaconId.id(beaconId) &
            row.state.equals(PhantomPendingForwardState.pending),
      )
      .exists();

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
ON CONFLICT DO NOTHING
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

  @override
  Future<List<PhantomForwardClaim>> claimForMerge(
    OwnerGraphScope scope, {
    required String phantomId,
    required String senderId,
    required String mergeId,
    required String recipientId,
  }) async {
    requireOwnerGraphScope(_database, scope, senderId);
    final rows = await _database.customWriteReturning(
      r'''
WITH claimed AS (
  UPDATE public.phantom_pending_forward
  SET state = 'claimed', merge_id = $3, recipient_id = $4
  WHERE phantom_id = $1 AND sender_id = $2 AND state = 'pending'
  RETURNING id, beacon_id, parent_forward_edge_id, created_at
)
SELECT id, beacon_id, parent_forward_edge_id FROM claimed ORDER BY created_at, id
''',
      variables: [
        Variable.withString(phantomId),
        Variable.withString(senderId),
        Variable.withString(mergeId),
        Variable.withString(recipientId),
      ],
      updates: {_database.phantomPendingForwards},
      updateKind: UpdateKind.update,
    );
    return [
      for (final row in rows)
        (
          id: row.read<String>('id'),
          senderId: senderId,
          beaconId: row.read<String>('beacon_id'),
          parentForwardEdgeId: row.readNullable<String>(
            'parent_forward_edge_id',
          ),
          mergeId: mergeId,
        ),
    ];
  }

  @override
  Future<bool> lockParentChain(
    OwnerGraphScope scope,
    PhantomForwardClaim claim,
  ) {
    requireOwnerGraphScope(_database, scope, claim.senderId);
    return lockActiveForwardParentChain(_database, claim.parentForwardEdgeId);
  }

  @override
  Future<PhantomForwardDelivery?> lockClaim(
    OwnerGraphScope scope,
    PhantomForwardClaim claim,
  ) async {
    requireOwnerGraphScope(_database, scope, claim.senderId);
    final row = await _database
        .customSelect(
          r'''
SELECT f.recipient_id, f.note
FROM public.phantom_pending_forward f
JOIN public.phantom p ON p.id = f.phantom_id AND p.owner_id = f.sender_id
  AND p.current_merge_id = f.merge_id AND p.merged_user_id = f.recipient_id
WHERE f.id = $1 AND f.sender_id = $2 AND f.merge_id = $3
  AND f.state = 'claimed' AND f.beacon_id = $4
  AND f.parent_forward_edge_id IS NOT DISTINCT FROM $5
FOR UPDATE OF f
''',
          variables: [
            Variable.withString(claim.id),
            Variable.withString(claim.senderId),
            Variable.withString(claim.mergeId),
            Variable.withString(claim.beaconId),
            Variable<String>(claim.parentForwardEdgeId),
          ],
        )
        .getSingleOrNull();
    return row == null
        ? null
        : (
            recipientId: row.read<String>('recipient_id'),
            note: row.read<String>('note'),
          );
  }

  @override
  Future<void> resolve(
    OwnerGraphScope scope,
    PhantomForwardClaim claim,
    PhantomForwardResolution resolution,
  ) async {
    requireOwnerGraphScope(_database, scope, claim.senderId);
    final (state, edgeId, reason) = switch (resolution) {
      PhantomForwardDelivered(:final edgeId) => ('delivered', edgeId, null),
      PhantomForwardLapsed(:final reason) => ('lapsed', null, reason),
    };
    final updated = await _database.customUpdate(
      r'''
UPDATE public.phantom_pending_forward
SET state = $4, forward_edge_id = $5, lapse_reason = $6, resolved_at = now()
WHERE id = $1 AND sender_id = $2 AND merge_id = $3 AND state = 'claimed'
''',
      variables: [
        Variable.withString(claim.id),
        Variable.withString(claim.senderId),
        Variable.withString(claim.mergeId),
        Variable.withString(state),
        Variable<String>(edgeId),
        Variable<String>(reason),
      ],
      updates: {_database.phantomPendingForwards},
      updateKind: UpdateKind.update,
    );
    if (updated != 1) {
      throw StateError('Lost pending forward claim ${claim.id}');
    }
  }
}
