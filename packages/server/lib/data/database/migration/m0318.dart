part of '_migrations.dart';

/// The forwarding picker reads involvement before sending. Expose the same
/// access decision through Hasura while retaining the existing forward rules.
final m0318 = Migration('0318', [
  r'''
CREATE OR REPLACE FUNCTION public.beacon_get_viewer_can_forward(beacon_row public.beacon, hasura_session json) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
SELECT COALESCE(
  beacon_row.status IN (0, 7, 8)
  AND (beacon_row.forward_policy = 1 OR beacon_row.user_id = viewer.id)
  AND public.beacon_can_read_involvement(beacon_row.id, viewer.id),
  false
)
FROM (VALUES (hasura_session ->> 'x-hasura-user-id')) AS viewer(id);
$$
''',
]);
