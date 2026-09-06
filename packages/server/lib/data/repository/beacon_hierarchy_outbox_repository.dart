import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:postgres/postgres.dart' show TypedValue, Type;
import 'package:tentura_root/domain/entity/beacon_hierarchy_delivery_direction.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_event.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/consts/beacon_hierarchy_consts.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_outbox_port.dart';
import 'package:tentura_server/utils/id.dart';

import '../database/tentura_db.dart';

@Singleton(as: BeaconHierarchyOutboxPort)
class BeaconHierarchyOutboxRepository implements BeaconHierarchyOutboxPort {
  const BeaconHierarchyOutboxRepository(this._database);

  final TenturaDb _database;

  @override
  Future<BeaconHierarchyEvent> recordEvent({
    required String sourceBeaconId,
    required BeaconStatus fromStatus,
    required BeaconStatus toStatus,
    required DateTime occurredAt,
    String? actorUserId,
  }) async {
    final eventId = generateId('HE');
    final rows = await _database
        .customSelect(
          actorUserId == null
              ? r'''
WITH locked AS (
  SELECT id FROM public.beacon WHERE id = $1 FOR UPDATE
),
next_seq AS (
  UPDATE public.beacon b
  SET hierarchy_event_sequence = b.hierarchy_event_sequence + 1
  FROM locked
  WHERE b.id = locked.id
  RETURNING b.hierarchy_event_sequence AS seq
),
inserted AS (
  INSERT INTO public.beacon_hierarchy_events (
    id, source_beacon_id, source_sequence, from_status, to_status,
    occurred_at, actor_user_id
  )
  SELECT $2, $1, next_seq.seq, $3, $4, $5::timestamptz, NULL
  FROM next_seq
  RETURNING *
)
SELECT * FROM inserted
'''
              : r'''
WITH locked AS (
  SELECT id FROM public.beacon WHERE id = $1 FOR UPDATE
),
next_seq AS (
  UPDATE public.beacon b
  SET hierarchy_event_sequence = b.hierarchy_event_sequence + 1
  FROM locked
  WHERE b.id = locked.id
  RETURNING b.hierarchy_event_sequence AS seq
),
inserted AS (
  INSERT INTO public.beacon_hierarchy_events (
    id, source_beacon_id, source_sequence, from_status, to_status,
    occurred_at, actor_user_id
  )
  SELECT $2, $1, next_seq.seq, $3, $4, $5::timestamptz, $6
  FROM next_seq
  RETURNING *
)
SELECT * FROM inserted
''',
          variables: actorUserId == null
              ? [
                  Variable<String>(sourceBeaconId),
                  Variable<String>(eventId),
                  Variable<int>(fromStatus.smallintValue),
                  Variable<int>(toStatus.smallintValue),
                  Variable(TypedValue(Type.timestampTz, occurredAt.toUtc())),
                ]
              : [
                  Variable<String>(sourceBeaconId),
                  Variable<String>(eventId),
                  Variable<int>(fromStatus.smallintValue),
                  Variable<int>(toStatus.smallintValue),
                  Variable(TypedValue(Type.timestampTz, occurredAt.toUtc())),
                  Variable<String>(actorUserId),
                ],
        )
        .get();
    final row = rows.single;
    return _eventFromRow(row);
  }

  @override
  Future<void> insertDeliveryTargets({
    required BeaconHierarchyEvent event,
    required List<BeaconHierarchyDeliveryTarget> targets,
  }) async {
    if (targets.isEmpty) {
      return;
    }
    for (final target in targets) {
      await _database.customStatement(
        r'''
INSERT INTO public.beacon_hierarchy_deliveries (
  event_id,
  target_beacon_id,
  direction,
  state,
  next_attempt_at
) VALUES ($1, $2, $3, 'pending', now())
ON CONFLICT (event_id, target_beacon_id) DO NOTHING
''',
        [
          target.eventId,
          target.targetBeaconId,
          _directionWire(target.direction),
        ],
      );
    }
  }

  @override
  Future<void> insertTopologyDeliveryTargets({
    required String sourceBeaconId,
    required String eventId,
  }) async {
    await _database.customStatement(
      r'''
WITH RECURSIVE descendants AS (
  SELECT b.id
  FROM public.beacon b
  WHERE b.parent_beacon_id = $1
    AND b.published_at IS NOT NULL
  UNION ALL
  SELECT child.id
  FROM public.beacon child
  JOIN descendants d ON child.parent_beacon_id = d.id
  WHERE child.published_at IS NOT NULL
),
ancestor AS (
  SELECT p.id
  FROM public.beacon source
  JOIN public.beacon p ON p.id = source.parent_beacon_id
  WHERE source.id = $1
    AND p.published_at IS NOT NULL
),
targets AS (
  SELECT id AS target_beacon_id, 'ancestor'::text AS direction
  FROM descendants
  UNION ALL
  SELECT id, 'child'::text FROM ancestor
)
INSERT INTO public.beacon_hierarchy_deliveries (
  event_id,
  target_beacon_id,
  direction,
  state,
  next_attempt_at
)
SELECT $2, target_beacon_id, direction, 'pending', now()
FROM targets
WHERE target_beacon_id <> $1
ON CONFLICT (event_id, target_beacon_id) DO NOTHING
''',
      [sourceBeaconId, eventId],
    );
  }

  /// Set-based recursive traversal of immutable parent edges for lifecycle targets.
  Future<List<BeaconHierarchyDeliveryTarget>> collectPublishedTopologyTargets({
    required String sourceBeaconId,
    required String eventId,
  }) async {
    final rows = await _database
        .customSelect(
          r'''
WITH RECURSIVE descendants AS (
  SELECT b.id
  FROM public.beacon b
  WHERE b.parent_beacon_id = $1
    AND b.published_at IS NOT NULL
  UNION ALL
  SELECT child.id
  FROM public.beacon child
  JOIN descendants d ON child.parent_beacon_id = d.id
  WHERE child.published_at IS NOT NULL
),
ancestor AS (
  SELECT p.id
  FROM public.beacon source
  JOIN public.beacon p ON p.id = source.parent_beacon_id
  WHERE source.id = $1
    AND p.published_at IS NOT NULL
),
targets AS (
  SELECT id AS target_beacon_id, 'ancestor'::text AS direction
  FROM descendants
  UNION ALL
  SELECT id, 'child'::text FROM ancestor
)
SELECT target_beacon_id, direction
FROM targets
WHERE target_beacon_id <> $1
ORDER BY direction, target_beacon_id
''',
          variables: [Variable<String>(sourceBeaconId)],
        )
        .get();
    return [
      for (final row in rows)
        BeaconHierarchyDeliveryTarget(
          eventId: eventId,
          targetBeaconId: row.read<String>('target_beacon_id'),
          direction: _directionFromWire(row.read<String>('direction')),
        ),
    ];
  }

  @override
  Future<List<BeaconHierarchyDeliveryTarget>> claimDueDeliveries({
    required String leaseOwner,
    required int limit,
  }) async {
    final now = DateTime.timestamp().toUtc();
    final rows = await _database
        .customSelect(
          r'''
WITH candidates AS (
  SELECT
    d.event_id,
    d.target_beacon_id,
    d.direction,
    e.source_beacon_id,
    e.source_sequence,
    e.occurred_at
  FROM public.beacon_hierarchy_deliveries d
  JOIN public.beacon_hierarchy_events e ON e.id = d.event_id
  WHERE (
      (d.state = 'pending' AND d.next_attempt_at <= $1::timestamptz)
      OR (d.state = 'leased' AND d.lease_until <= $1::timestamptz)
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.beacon_hierarchy_deliveries earlier
      JOIN public.beacon_hierarchy_events ee ON ee.id = earlier.event_id
      WHERE earlier.target_beacon_id = d.target_beacon_id
        AND ee.source_beacon_id = e.source_beacon_id
        AND ee.source_sequence < e.source_sequence
        AND earlier.state IN ('pending', 'leased')
    )
  ORDER BY d.next_attempt_at, e.occurred_at, d.event_id, d.target_beacon_id
  FOR UPDATE SKIP LOCKED
  LIMIT $2
),
claimed AS (
  UPDATE public.beacon_hierarchy_deliveries d
  SET
    state = 'leased',
    attempt_count = d.attempt_count + 1,
    lease_owner = $3,
    lease_until = $1::timestamptz + interval '2 minutes'
  FROM candidates c
  WHERE d.event_id = c.event_id
    AND d.target_beacon_id = c.target_beacon_id
  RETURNING d.event_id, d.target_beacon_id, d.direction
)
SELECT event_id, target_beacon_id, direction FROM claimed
''',
          variables: [
            Variable(TypedValue(Type.timestampTz, now)),
            Variable<int>(limit),
            Variable<String>(leaseOwner),
          ],
        )
        .get();
    return [
      for (final row in rows)
        BeaconHierarchyDeliveryTarget(
          eventId: row.read<String>('event_id'),
          targetBeaconId: row.read<String>('target_beacon_id'),
          direction: _directionFromWire(row.read<String>('direction')),
        ),
    ];
  }

  @override
  Future<void> markDeliveryDelivered({
    required String eventId,
    required String targetBeaconId,
    required String leaseOwner,
    String? noticeMessageId,
  }) => _database.customStatement(
    r'''
UPDATE public.beacon_hierarchy_deliveries
SET
  state = 'delivered',
  completed_at = now(),
  notice_message_id = $4,
  lease_owner = NULL,
  lease_until = NULL
WHERE event_id = $1
  AND target_beacon_id = $2
  AND state = 'leased'
  AND lease_owner = $3
''',
    [eventId, targetBeaconId, leaseOwner, noticeMessageId],
  );

  @override
  Future<void> markDeliverySuppressed({
    required String eventId,
    required String targetBeaconId,
    required String leaseOwner,
  }) => _database.customStatement(
    r'''
UPDATE public.beacon_hierarchy_deliveries
SET
  state = 'suppressed',
  completed_at = now(),
  lease_owner = NULL,
  lease_until = NULL
WHERE event_id = $1
  AND target_beacon_id = $2
  AND state = 'leased'
  AND lease_owner = $3
''',
    [eventId, targetBeaconId, leaseOwner],
  );

  @override
  Future<void> markDeliveryParked({
    required String eventId,
    required String targetBeaconId,
    required String leaseOwner,
    required String safeErrorCode,
  }) => _database.customStatement(
    r'''
UPDATE public.beacon_hierarchy_deliveries
SET
  state = 'parked',
  completed_at = now(),
  last_safe_error_code = $4,
  lease_owner = NULL,
  lease_until = NULL
WHERE event_id = $1
  AND target_beacon_id = $2
  AND state = 'leased'
  AND lease_owner = $3
''',
    [eventId, targetBeaconId, leaseOwner, safeErrorCode],
  );

  static BeaconHierarchyEvent _eventFromRow(QueryRow row) => BeaconHierarchyEvent(
    eventId: row.read<String>('id'),
    sourceBeaconId: row.read<String>('source_beacon_id'),
    sourceSequence: row.read<int>('source_sequence'),
    fromStatus: BeaconStatus.fromSmallint(row.read<int>('from_status')),
    toStatus: BeaconStatus.fromSmallint(row.read<int>('to_status')),
    occurredAt: DateTime.parse(row.read<String>('occurred_at')).toUtc(),
    actorUserId: row.readNullable<String>('actor_user_id'),
  );

  static String _directionWire(BeaconHierarchyDeliveryDirection direction) =>
      switch (direction) {
        BeaconHierarchyDeliveryDirection.ancestor =>
          BeaconHierarchyDeliveryDirectionWire.ancestor,
        BeaconHierarchyDeliveryDirection.child =>
          BeaconHierarchyDeliveryDirectionWire.child,
      };

  static BeaconHierarchyDeliveryDirection _directionFromWire(String wire) =>
      switch (wire) {
        BeaconHierarchyDeliveryDirectionWire.child =>
          BeaconHierarchyDeliveryDirection.child,
        _ => BeaconHierarchyDeliveryDirection.ancestor,
      };
}
