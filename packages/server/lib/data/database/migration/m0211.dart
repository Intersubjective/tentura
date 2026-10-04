part of '_migrations.dart';

/// Post read model (plan §4.3): `beacon_get_viewer_can_forward` is the SQL
/// twin of `BeaconForwardPolicy.canForward` for a Hasura session, exposed as
/// the `viewer_can_forward` computed field on `beacon`.
final m0211 = Migration('0211', [
  r'''
CREATE FUNCTION public.beacon_get_viewer_can_forward(beacon_row public.beacon, hasura_session json) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
SELECT COALESCE(
  beacon_row.status IN (0, 7, 8)
  AND (
    beacon_row.forward_policy = 1
    OR beacon_row.user_id = (hasura_session ->> 'x-hasura-user-id')::TEXT
  ),
  false
);
$$
''',
]);
