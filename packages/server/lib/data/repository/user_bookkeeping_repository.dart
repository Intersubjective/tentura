import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/user_bookkeeping_result.dart';
import 'package:tentura_server/domain/port/user_bookkeeping_repository_port.dart';

import '../database/tentura_db.dart';

@Injectable(
  as: UserBookkeepingRepositoryPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class UserBookkeepingRepository implements UserBookkeepingRepositoryPort {
  UserBookkeepingRepository(this._database);

  final TenturaDb _database;

  @override
  Future<List<AdmittedOfferCoordinationGap>>
  listAdmittedOffersMissingCoordination(String authorUserId) async {
    final rows = await _database.customSelect(
      r'''
SELECT ho.beacon_id, ho.user_id AS offer_user_id, b.user_id AS author_user_id
FROM public.beacon_help_offer ho
JOIN public.beacon_participant bp
  ON bp.beacon_id = ho.beacon_id
 AND bp.user_id = ho.user_id
JOIN public.beacon b ON b.id = ho.beacon_id
WHERE b.user_id = $1
  AND ho.status = 0
  AND bp.room_access = 3
  AND NOT EXISTS (
    SELECT 1
    FROM public.beacon_help_offer_coordination c
    WHERE c.offer_beacon_id = ho.beacon_id
      AND c.offer_user_id = ho.user_id
  )
''',
      variables: [Variable<String>(authorUserId)],
      readsFrom: {},
    ).get();

    return [
      for (final row in rows)
        AdmittedOfferCoordinationGap(
          beaconId: row.read<String>('beacon_id'),
          offerUserId: row.read<String>('offer_user_id'),
          authorUserId: row.read<String>('author_user_id'),
        ),
    ];
  }

  @override
  Future<InboxReconcileResult> reconcileInboxForUser(String userId) =>
      _database.withMutatingUser(userId, () async {
        final repairedCount = await _database.customUpdate(
          r'''
WITH edge_latest AS (
  SELECT DISTINCT ON (fe.beacon_id)
    fe.beacon_id,
    fe.context,
    fe.created_at AS latest_forward_at,
    CASE
      WHEN char_length(fe.note) > 200 THEN substring(fe.note FROM 1 FOR 200)
      ELSE fe.note
    END AS latest_note_preview
  FROM public.beacon_forward_edge fe
  WHERE fe.recipient_id = $1
    AND fe.cancelled_at IS NULL
  ORDER BY fe.beacon_id, fe.created_at DESC
),
edge_counts AS (
  SELECT fe.beacon_id, COUNT(*)::int AS forward_count
  FROM public.beacon_forward_edge fe
  WHERE fe.recipient_id = $1
    AND fe.cancelled_at IS NULL
  GROUP BY fe.beacon_id
)
UPDATE public.inbox_item ii
SET
  forward_count = ec.forward_count,
  latest_forward_at = el.latest_forward_at,
  latest_note_preview = el.latest_note_preview,
  context = COALESCE(el.context, ii.context)
FROM edge_latest el
JOIN edge_counts ec ON ec.beacon_id = el.beacon_id
WHERE ii.user_id = $1
  AND ii.beacon_id = el.beacon_id
  AND (
    ii.forward_count IS DISTINCT FROM ec.forward_count
    OR ii.latest_forward_at IS DISTINCT FROM el.latest_forward_at
    OR ii.latest_note_preview IS DISTINCT FROM el.latest_note_preview
  )
''',
          variables: [Variable<String>(userId)],
          updates: {},
          updateKind: UpdateKind.update,
        );

        final insertedRows = await _database.customSelect(
          r'''
WITH edge_latest AS (
  SELECT DISTINCT ON (fe.beacon_id)
    fe.beacon_id,
    fe.context,
    fe.created_at AS latest_forward_at,
    CASE
      WHEN char_length(fe.note) > 200 THEN substring(fe.note FROM 1 FOR 200)
      ELSE fe.note
    END AS latest_note_preview
  FROM public.beacon_forward_edge fe
  WHERE fe.recipient_id = $1
    AND fe.cancelled_at IS NULL
  ORDER BY fe.beacon_id, fe.created_at DESC
),
edge_counts AS (
  SELECT fe.beacon_id, COUNT(*)::int AS forward_count
  FROM public.beacon_forward_edge fe
  WHERE fe.recipient_id = $1
    AND fe.cancelled_at IS NULL
  GROUP BY fe.beacon_id
),
inserted AS (
  INSERT INTO public.inbox_item (
    user_id,
    beacon_id,
    context,
    forward_count,
    latest_forward_at,
    latest_note_preview
  )
  SELECT
    $1,
    el.beacon_id,
    el.context,
    ec.forward_count,
    el.latest_forward_at,
    el.latest_note_preview
  FROM edge_latest el
  JOIN edge_counts ec ON ec.beacon_id = el.beacon_id
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.inbox_item ii
    WHERE ii.user_id = $1
      AND ii.beacon_id = el.beacon_id
  )
  RETURNING beacon_id
)
SELECT beacon_id FROM inserted
''',
          variables: [Variable<String>(userId)],
          readsFrom: {},
        ).get();

        final repairedBeaconIds = await _database.customSelect(
          r'''
WITH edge_latest AS (
  SELECT DISTINCT ON (fe.beacon_id)
    fe.beacon_id,
    fe.created_at AS latest_forward_at,
    CASE
      WHEN char_length(fe.note) > 200 THEN substring(fe.note FROM 1 FOR 200)
      ELSE fe.note
    END AS latest_note_preview
  FROM public.beacon_forward_edge fe
  WHERE fe.recipient_id = $1
    AND fe.cancelled_at IS NULL
  ORDER BY fe.beacon_id, fe.created_at DESC
),
edge_counts AS (
  SELECT fe.beacon_id, COUNT(*)::int AS forward_count
  FROM public.beacon_forward_edge fe
  WHERE fe.recipient_id = $1
    AND fe.cancelled_at IS NULL
  GROUP BY fe.beacon_id
)
SELECT ii.beacon_id
FROM public.inbox_item ii
JOIN edge_latest el ON el.beacon_id = ii.beacon_id
JOIN edge_counts ec ON ec.beacon_id = ii.beacon_id
WHERE ii.user_id = $1
''',
          variables: [Variable<String>(userId)],
          readsFrom: {},
        ).get();

        final beaconIds = {
          for (final row in insertedRows) row.read<String>('beacon_id'),
          for (final row in repairedBeaconIds) row.read<String>('beacon_id'),
        };

        return InboxReconcileResult(
          repairedCount: repairedCount,
          insertedCount: insertedRows.length,
          beaconIds: beaconIds.toList(growable: false),
        );
      });
}
