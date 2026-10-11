part of '_migrations.dart';

/// Post→Request budding facts (budding B2, Arch §2.1, §3.3).
///
/// - `post_effective_members(post)`: `E(P)` — the Post author (no participant
///   row needed) plus participants with `room_access = 3` that pass
///   `beacon_effective_admission`, minus users blocked with the Post author.
///   Empty for a Request.
/// - `post_bud_invite_facts(post, budder)`: one row per member of
///   `E(P) \ {budder}`: `warm` (first responder or Post author), `reason`
///   (0 eligible, 2 blocked with the budder, 4 availability-paused,
///   5 already holds a pending invite from the budder for this Post),
///   `has_written` (a non-system message in the Post) and `via_user_id` (the
///   sender of the member's latest active inbound edge on the Post).
///   Visibility (reason 3) is decided in Dart (`PostBudPort`); no `mr_*` here.
/// - `post_bud_pretick(post, budder)`: users the budder @mentioned in the
///   Post plus authors of replies to the budder's messages (D5).
final m0240 = Migration('0240', [
  r'''
CREATE FUNCTION public.post_effective_members(p_post text) RETURNS TABLE(user_id text)
    LANGUAGE sql STABLE
    AS $$
SELECT b.user_id
FROM public.beacon b
WHERE b.id = p_post AND b.kind = 1
UNION
SELECT bp.user_id
FROM public.beacon b
JOIN public.beacon_participant bp ON bp.beacon_id = b.id
WHERE b.id = p_post
  AND b.kind = 1
  AND bp.room_access = 3
  AND public.beacon_effective_admission(b.id, bp.user_id)
  AND NOT public.block_hides(b.user_id, bp.user_id)
$$
''',
  r'''
CREATE FUNCTION public.post_bud_invite_facts(p_post text, p_budder text) RETURNS TABLE(user_id text, warm boolean, reason smallint, has_written boolean, via_user_id text)
    LANGUAGE sql STABLE
    AS $$
SELECT
  m.user_id,
  (m.user_id = b.user_id
     OR EXISTS (
       SELECT 1 FROM public.post_first_response fr
       WHERE fr.beacon_id = p_post AND fr.user_id = m.user_id)),
  (CASE
     WHEN public.block_hides(p_budder, m.user_id) THEN 2
     WHEN EXISTS (
       SELECT 1 FROM public.user_availability ua
       WHERE ua.user_id = m.user_id
         AND ua.resume_on > public.utc_today()) THEN 4
     WHEN EXISTS (
       SELECT 1 FROM public.beacon_author_invite i
       WHERE i.status = 0
         AND i.inviter_id = p_budder
         AND i.invitee_id = m.user_id
         AND i.source_post_id = p_post) THEN 5
     ELSE 0
   END)::smallint,
  EXISTS (
    SELECT 1 FROM public.beacon_room_message rm
    WHERE rm.beacon_id = p_post
      AND rm.author_id = m.user_id
      AND rm.system_message_kind IS NULL),
  (SELECT e.sender_id
   FROM public.beacon_forward_edge e
   WHERE e.beacon_id = p_post
     AND e.recipient_id = m.user_id
     AND e.cancelled_at IS NULL
   ORDER BY e.created_at DESC, e.id DESC
   LIMIT 1)
FROM public.post_effective_members(p_post) m
JOIN public.beacon b ON b.id = p_post
WHERE m.user_id <> p_budder
$$
''',
  r'''
CREATE FUNCTION public.post_bud_pretick(p_post text, p_budder text) RETURNS TABLE(user_id text)
    LANGUAGE sql STABLE
    AS $$
SELECT DISTINCT u.id
FROM (
  SELECT unnest(rm.mentions) AS id
  FROM public.beacon_room_message rm
  WHERE rm.beacon_id = p_post
    AND rm.author_id = p_budder
    AND rm.system_message_kind IS NULL
  UNION
  SELECT r.author_id
  FROM public.beacon_room_message r
  JOIN public.beacon_room_message t ON t.id = r.reply_to_message_id
  WHERE r.beacon_id = p_post
    AND t.beacon_id = p_post
    AND t.author_id = p_budder
    AND r.author_id IS NOT NULL
    AND r.system_message_kind IS NULL
) u
WHERE u.id <> p_budder AND u.id <> ''
$$
''',
]);
