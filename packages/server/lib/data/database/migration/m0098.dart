part of '_migrations.dart';

/// Relationship-scoped beacon visibility SQL predicates (ADR 0008 phase 1).
final m0098 = Migration('0098', [
  r'''
CREATE OR REPLACE FUNCTION public.user_is_mutual_friend(
  p_user_a text,
  p_user_b text
) RETURNS boolean
  LANGUAGE sql
  STABLE
  AS $$
SELECT EXISTS (
  SELECT 1 FROM public.vote_user vu
  WHERE vu.subject = p_user_a
    AND vu.object = p_user_b
    AND vu.amount > 0
) AND EXISTS (
  SELECT 1 FROM public.vote_user vu
  WHERE vu.subject = p_user_b
    AND vu.object = p_user_a
    AND vu.amount > 0
);
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.beacon_can_read_content(
  p_beacon_id text,
  p_viewer_id text
) RETURNS boolean
  LANGUAGE sql
  STABLE
  AS $$
SELECT COALESCE((
  SELECT CASE
    WHEN b.status = 3 THEN b.user_id = p_viewer_id
    WHEN b.status = 2 THEN false
    WHEN b.user_id = p_viewer_id THEN true
    WHEN EXISTS (
      SELECT 1 FROM public.beacon_forward_edge fe
      WHERE fe.beacon_id = p_beacon_id
        AND fe.recipient_id = p_viewer_id
        AND fe.cancelled_at IS NULL
    ) THEN true
    WHEN EXISTS (
      SELECT 1 FROM public.beacon_participant bp
      WHERE bp.beacon_id = p_beacon_id
        AND bp.user_id = p_viewer_id
        AND (bp.role = 1 OR bp.room_access = 3)
    ) THEN true
    WHEN EXISTS (
      SELECT 1 FROM public.beacon_help_offer ho
      WHERE ho.beacon_id = p_beacon_id
        AND ho.user_id = p_viewer_id
        AND ho.status = 0
    ) THEN true
    WHEN public.user_is_mutual_friend(p_viewer_id, b.user_id) THEN true
    ELSE false
  END
  FROM public.beacon b
  WHERE b.id = p_beacon_id
), false);
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.beacon_can_read_involvement(
  p_beacon_id text,
  p_viewer_id text
) RETURNS boolean
  LANGUAGE sql
  STABLE
  AS $$
SELECT public.beacon_can_read_content(p_beacon_id, p_viewer_id)
  AND (
    EXISTS (
      SELECT 1 FROM public.beacon b
      WHERE b.id = p_beacon_id AND b.user_id = p_viewer_id
    )
    OR EXISTS (
      SELECT 1 FROM public.beacon_forward_edge fe
      WHERE fe.beacon_id = p_beacon_id
        AND (fe.sender_id = p_viewer_id OR fe.recipient_id = p_viewer_id)
        AND fe.cancelled_at IS NULL
    )
    OR EXISTS (
      SELECT 1 FROM public.beacon_help_offer ho
      WHERE ho.beacon_id = p_beacon_id
        AND ho.user_id = p_viewer_id
        AND ho.status = 0
    )
    OR EXISTS (
      SELECT 1 FROM public.beacon_participant bp
      WHERE bp.beacon_id = p_beacon_id
        AND bp.user_id = p_viewer_id
        AND (bp.role = 1 OR bp.room_access = 3)
    )
    OR EXISTS (
      SELECT 1 FROM public.beacon b
      WHERE b.id = p_beacon_id
        AND public.user_is_mutual_friend(p_viewer_id, b.user_id)
    )
  );
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.beacon_can_read_tombstone(
  p_beacon_id text,
  p_viewer_id text
) RETURNS boolean
  LANGUAGE sql
  STABLE
  AS $$
SELECT COALESCE((
  SELECT CASE
    WHEN b.status <> 2 THEN false
    WHEN b.user_id = p_viewer_id THEN true
    WHEN EXISTS (
      SELECT 1 FROM public.inbox_item ii
      WHERE ii.beacon_id = p_beacon_id AND ii.user_id = p_viewer_id
    ) THEN true
    WHEN EXISTS (
      SELECT 1 FROM public.beacon_forward_edge fe
      WHERE fe.beacon_id = p_beacon_id
        AND (fe.sender_id = p_viewer_id OR fe.recipient_id = p_viewer_id)
    ) THEN true
    WHEN EXISTS (
      SELECT 1 FROM public.beacon_help_offer ho
      WHERE ho.beacon_id = p_beacon_id AND ho.user_id = p_viewer_id
    ) THEN true
    WHEN EXISTS (
      SELECT 1 FROM public.beacon_participant bp
      WHERE bp.beacon_id = p_beacon_id AND bp.user_id = p_viewer_id
    ) THEN true
    ELSE false
  END
  FROM public.beacon b
  WHERE b.id = p_beacon_id
), false);
$$;
''',
]);
