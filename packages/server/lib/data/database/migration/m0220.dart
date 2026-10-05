part of '_migrations.dart';

/// `user.shares_episode_with_viewer` (#159, #104): the Request showcase puts
/// acquaintances first in its team strip. An acquaintance is someone the
/// viewer trusts (`my_vote > 0`, already exposed) or someone the viewer has
/// worked a Request with before: both were "in" it, as its author or as an
/// admitted participant (`room_access = 3`). Deleted Requests do not count.
///
/// The field only answers yes/no for a user row the viewer can already read;
/// the `user` select filter (`hidden_for_viewer`) still hides blocked users.
final m0220 = Migration('0220', [
  r'''
CREATE FUNCTION public.user_get_shares_episode_with_viewer(user_row public."user", hasura_session json) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
WITH viewer AS (
  SELECT nullif(trim(hasura_session ->> 'x-hasura-user-id'), '') AS id
),
viewer_beacons AS (
  SELECT b.id
  FROM public.beacon b, viewer v
  WHERE b.user_id = v.id
    AND b.kind = 0
    AND b.status <> 2
  UNION
  SELECT bp.beacon_id
  FROM public.beacon_participant bp
  JOIN public.beacon b ON b.id = bp.beacon_id
  JOIN viewer v ON bp.user_id = v.id
  WHERE bp.room_access = 3
    AND b.kind = 0
    AND b.status <> 2
)
SELECT COALESCE((SELECT v.id IS NOT NULL AND v.id <> user_row.id FROM viewer v), false)
  AND EXISTS (
    SELECT 1
    FROM viewer_beacons vb
    WHERE EXISTS (
        SELECT 1 FROM public.beacon b
        WHERE b.id = vb.id AND b.user_id = user_row.id
      )
      OR EXISTS (
        SELECT 1 FROM public.beacon_participant bp
        WHERE bp.beacon_id = vb.id
          AND bp.user_id = user_row.id
          AND bp.room_access = 3
      )
  );
$$
''',
  '''
COMMENT ON FUNCTION public.user_get_shares_episode_with_viewer(public."user", json) IS
  'Hasura computed field user.shares_episode_with_viewer: viewer and user were both in a non-deleted Request (author or admitted)';
''',
]);
