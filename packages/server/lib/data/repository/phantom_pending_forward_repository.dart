import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/phantom_pending_forward.dart';
import 'package:tentura_server/domain/port/owner_graph_transaction_port.dart';
import 'package:tentura_server/domain/port/phantom_pending_forward_repository_port.dart';

import '../database/tentura_db.dart';
import 'attention_dispatch_repository.dart';
import 'forward_parent_chain_lock.dart';
import 'owner_graph_unit_of_work.dart';

@LazySingleton(as: PhantomPendingForwardRepositoryPort)
final class PhantomPendingForwardRepository
    implements PhantomPendingForwardRepositoryPort {
  PhantomPendingForwardRepository(
    this._database, [
    AttentionDispatchRepository? attention,
  ]) : _attention = attention ?? AttentionDispatchRepository(_database);

  final TenturaDb _database;
  final AttentionDispatchRepository _attention;

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
  Future<List<PhantomForwardClaim>> assignForMerge(
    OwnerGraphScope scope, {
    required String phantomId,
    required String senderId,
    required String mergeId,
    required String recipientId,
    required PhantomForwardDeliverySource source,
  }) async {
    requireOwnerGraphScope(_database, scope, senderId);
    final rows = await _database.customWriteReturning(
      r'''
WITH assigned AS (
  UPDATE public.phantom_pending_forward
  SET state = $5, merge_id = $3, recipient_id = $4
  WHERE phantom_id = $1 AND sender_id = $2 AND state = 'pending'
  RETURNING id, sender_id, beacon_id, parent_forward_edge_id, merge_id, created_at
)
SELECT id, sender_id, beacon_id, parent_forward_edge_id, merge_id
FROM assigned ORDER BY created_at, id
''',
      variables: [
        Variable.withString(phantomId),
        Variable.withString(senderId),
        Variable.withString(mergeId),
        Variable.withString(recipientId),
        Variable.withString(source.state.name),
      ],
      updates: {_database.phantomPendingForwards},
      updateKind: UpdateKind.update,
    );
    if (source == PhantomForwardDeliverySource.inviteClaim) {
      return rows.map(_claim).toList();
    }
    if (rows.isEmpty) return const [];
    final recipient = await _database
        .customSelect(
          r'SELECT display_name FROM public."user" WHERE id = $1',
          variables: [Variable.withString(recipientId)],
        )
        .getSingle();
    final displayName = recipient.read<String>('display_name');
    for (final row in rows) {
      await _attention.recordRequestForwardOffered(
        ownerId: senderId,
        beaconId: row.read<String>('beacon_id'),
        pendingForwardId: row.read<String>('id'),
        mergeId: mergeId,
        displayName: displayName,
      );
    }
    return const [];
  }

  @override
  Future<List<PhantomForwardClaim>> findClaims() async {
    final rows = await _database.customSelect('''
SELECT id, sender_id, beacon_id, parent_forward_edge_id, merge_id
FROM public.phantom_pending_forward
WHERE state = 'claimed'
ORDER BY created_at, id
''').get();
    return rows.map(_claim).toList();
  }

  static PhantomForwardClaim _claim(QueryRow row) => (
    id: row.read<String>('id'),
    senderId: row.read<String>('sender_id'),
    beaconId: row.read<String>('beacon_id'),
    parentForwardEdgeId: row.readNullable<String>('parent_forward_edge_id'),
    mergeId: row.readNullable<String>('merge_id'),
  );

  @override
  Future<bool> lockParentChain(
    OwnerGraphScope scope,
    PhantomForwardClaim claim,
  ) {
    requireOwnerGraphScope(_database, scope, claim.senderId);
    return lockActiveForwardParentChain(_database, claim.parentForwardEdgeId);
  }

  @override
  Future<PhantomForwardClaimTarget?> lockDelivery(
    OwnerGraphScope scope,
    PhantomForwardClaim claim, {
    required PhantomForwardDeliverySource source,
  }) async {
    requireOwnerGraphScope(_database, scope, claim.senderId);
    final row = await _database
        .customSelect(
          r'''
SELECT f.note,
       CASE WHEN f.merge_id = p.current_merge_id AND f.recipient_id = p.merged_user_id
            THEN f.recipient_id END AS current_recipient_id
FROM public.phantom_pending_forward f
JOIN public.phantom p ON p.id = f.phantom_id AND p.owner_id = f.sender_id
WHERE f.id = $1 AND f.sender_id = $2 AND f.merge_id IS NOT DISTINCT FROM $3
  AND f.state = $6 AND f.beacon_id = $4
  AND f.parent_forward_edge_id IS NOT DISTINCT FROM $5
FOR UPDATE OF f
''',
          variables: [
            Variable.withString(claim.id),
            Variable.withString(claim.senderId),
            Variable<String>(claim.mergeId),
            Variable.withString(claim.beaconId),
            Variable<String>(claim.parentForwardEdgeId),
            Variable.withString(source.state.name),
          ],
        )
        .getSingleOrNull();
    if (row == null) return null;
    final recipientId = row.readNullable<String>('current_recipient_id');
    return recipientId == null
        ? const PhantomForwardRecipientGone()
        : PhantomForwardDelivery(
            recipientId: recipientId,
            note: row.read<String>('note'),
          );
  }

  @override
  Future<void> resolve(
    OwnerGraphScope scope,
    PhantomForwardClaim claim,
    PhantomForwardResolution resolution, {
    PhantomForwardDeliverySource source =
        PhantomForwardDeliverySource.inviteClaim,
  }) async {
    requireOwnerGraphScope(_database, scope, claim.senderId);
    final (state, edgeId, reason) = switch (resolution) {
      PhantomForwardDelivered(:final edgeId) => ('delivered', edgeId, null),
      PhantomForwardLapsed(:final reason) => ('lapsed', null, reason),
    };
    final updated = await _database.customUpdate(
      r'''
UPDATE public.phantom_pending_forward
SET state = $4, forward_edge_id = $5, lapse_reason = $6, resolved_at = now()
WHERE id = $1 AND sender_id = $2 AND merge_id IS NOT DISTINCT FROM $3
  AND state = $7
''',
      variables: [
        Variable.withString(claim.id),
        Variable.withString(claim.senderId),
        Variable<String>(claim.mergeId),
        Variable.withString(state),
        Variable<String>(edgeId),
        Variable<String>(reason),
        Variable.withString(source.state.name),
      ],
      updates: {_database.phantomPendingForwards},
      updateKind: UpdateKind.update,
    );
    if (updated != 1) {
      throw StateError('Lost pending forward claim ${claim.id}');
    }
  }

  @override
  Future<void> recordJoinerCard(
    OwnerGraphScope scope,
    PhantomForwardClaim claim,
    PhantomForwardDelivery delivery,
  ) {
    requireOwnerGraphScope(_database, scope, claim.senderId);
    return _attention.recordRequestForwardLapsed(
      senderId: claim.senderId,
      recipientId: delivery.recipientId,
      pendingForwardId: claim.id,
    );
  }
}
