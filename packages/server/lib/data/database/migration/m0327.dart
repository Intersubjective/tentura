part of '_migrations.dart';

/// Let PostgreSQL inline the forwarding flag into Hasura's list queries.
final m0327 = Migration('0327', [
  r'''
CREATE OR REPLACE FUNCTION public.beacon_get_viewer_can_forward(beacon_row public.beacon, hasura_session json) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
SELECT COALESCE(
  beacon_row.status IN (0, 7, 8)
  AND (beacon_row.forward_policy = 1 OR beacon_row.user_id = (hasura_session ->> 'x-hasura-user-id'))
  AND public.beacon_can_read_involvement(beacon_row.id, hasura_session ->> 'x-hasura-user-id'),
  false
);
$$
''',
]);
