part of '_migrations.dart';

/// Legacy block-withdrawn helpers (offer `status = 1`,
/// `withdraw_reason = 'blocked'`) were taken out of the room by m0253 but
/// stayed assigned to live plan steps (`coordination_item` kind 6, status 0)
/// and kept a pending `beacon_plan_member` state. Frees them the way
/// `BeaconPlanCase.unassignOnLeave` does: clears `target_person_id` and
/// `pending_from_seq`. Someone still admitted (author, steward, addressee,
/// room_access 3) keeps their steps.
///
/// No `beacon_plan_revision` (kind 5) is written: building the PlanSnapshot
/// JSON in SQL is not worth it for data that is probably empty, so the
/// history shows no entry for this one-off repair.
///
/// Data only and idempotent: a second run finds no assigned live steps.
final m0275 = Migration('0275', [
  '''
WITH affected AS (
  SELECT DISTINCT ci.beacon_id, ci.target_person_id AS user_id
  FROM public.coordination_item ci
  JOIN public.beacon b ON b.id = ci.beacon_id
  JOIN public.beacon_help_offer o
    ON o.beacon_id = ci.beacon_id AND o.user_id = ci.target_person_id
  JOIN public.beacon_participant p
    ON p.beacon_id = ci.beacon_id AND p.user_id = ci.target_person_id
  WHERE ci.kind = 6 AND ci.status = 0
    AND o.status = 1 AND o.withdraw_reason = 'blocked'
    AND p.room_access = 0 AND p.role NOT IN (1, 6)
    AND b.user_id <> ci.target_person_id
    AND NOT EXISTS (
      SELECT 1 FROM public.beacon_steward s
      WHERE s.beacon_id = ci.beacon_id AND s.user_id = ci.target_person_id
    )
),
cleared AS (
  UPDATE public.beacon_plan_member m
  SET pending_from_seq = NULL
  FROM affected a
  WHERE m.beacon_id = a.beacon_id AND m.user_id = a.user_id
    AND m.pending_from_seq IS NOT NULL
)
UPDATE public.coordination_item ci
SET target_person_id = NULL, updated_at = now()
FROM affected a
WHERE ci.kind = 6 AND ci.status = 0
  AND ci.beacon_id = a.beacon_id AND ci.target_person_id = a.user_id
''',
]);
