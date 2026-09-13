part of '_migrations.dart';

/// Responsibility scope base set (authored ∪ active help offers) for My Work / Activity.
final m0168 = Migration('0168', [
  r'''
CREATE OR REPLACE FUNCTION public.responsibility_scope_base_beacons(
  p_account_id text
) RETURNS TABLE(beacon_id text)
  LANGUAGE sql
  STABLE
  SECURITY INVOKER
  SET search_path = public, pg_temp
  AS $$
SELECT b.id
FROM public.beacon b
WHERE b.user_id = p_account_id
  AND b.status <> 2
UNION
SELECT ho.beacon_id
FROM public.beacon_help_offer ho
INNER JOIN public.beacon b ON b.id = ho.beacon_id
WHERE ho.user_id = p_account_id
  AND ho.status = 0
  AND b.status <> 2;
$$;
''',
]);
