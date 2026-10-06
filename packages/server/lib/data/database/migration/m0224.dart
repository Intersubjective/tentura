part of '_migrations.dart';

/// Request plan («либретто», #220), notifications (plan §3.2, §4.5, §4.7).
///
/// - `responsibility_scope_base_beacons` gains the `planAssignee` branch: a
///   person with a live step (ticked or not) in a Request that still allows
///   coordination, while admitted, is responsible for it. Their plan receipts
///   therefore stay on My Work and never reach For You (owner rule D12).
///   The first two branches are the m0213 body verbatim; the parameter name,
///   `STABLE` and `search_path` are unchanged.
/// - `beacon_plan_sweep_mark` records which time phase of which step the
///   sweep already handled (`PlanSweepPhase.key`). A phase is claimed even when it ends up recording nothing
///   (a step that is not the assignee's current one owes no obligation yet),
///   so the occurrence log alone cannot serve as the claim.
final m0224 = Migration('0224', [
  r'''
CREATE OR REPLACE FUNCTION public.responsibility_scope_base_beacons(p_account_id text) RETURNS TABLE(beacon_id text)
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
SELECT b.id
FROM public.beacon b
WHERE b.user_id = p_account_id
  AND b.kind = 0
  AND b.status <> 2
UNION
SELECT ho.beacon_id
FROM public.beacon_help_offer ho
INNER JOIN public.beacon b ON b.id = ho.beacon_id
WHERE ho.user_id = p_account_id
  AND ho.status = 0
  AND b.kind = 0
  AND b.status <> 2
UNION
SELECT ci.beacon_id
FROM public.coordination_item ci
INNER JOIN public.beacon b ON b.id = ci.beacon_id
WHERE ci.kind = 6
  AND ci.status = 0
  AND ci.target_person_id = p_account_id
  AND b.kind = 0
  AND b.status IN (0, 5, 7, 8)
  AND public.beacon_effective_admission(ci.beacon_id, p_account_id);
$$
''',
  '''
CREATE TABLE public.beacon_plan_sweep_mark (
  key text PRIMARY KEY,
  beacon_id text NOT NULL REFERENCES public.beacon(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
)
''',
  '''
CREATE INDEX beacon_plan_sweep_mark_beacon
  ON public.beacon_plan_sweep_mark (beacon_id)
''',
]);
