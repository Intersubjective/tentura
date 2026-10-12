part of '_migrations.dart';

/// Budding E2 (Arch §10, I1, #284): repair open-family Requests (`kind = 0`,
/// status 0 / 7 / 8) with an admitted non-author, non-steward participant who
/// never acknowledged. Covers converted Requests and historical
/// `BeaconRoomAdmit` admits.
///
/// - Offer without an ack: the offer stays, room access reverts to none.
/// - No own confirmation: room access is removed (role-6 rows are deleted) and
///   a pending warm author invite with no source Post is created. It rides the
///   latest active inbound edge, or a new exempt author → person edge, so the
///   person can read the Request and the pinned row shows. The inbox row is
///   set to `needs_me`. No notification is sent.
/// - Acknowledged at least once: untouched.
///
/// Requests in review (status 5) or terminal are not modified, only reported.
final m0248 = Migration('0248', [
  r'''
DO $$
DECLARE
  r record;
  _edge text;
  _offers integer := 0;
  _unconfirmed integer := 0;
  _skipped text;
BEGIN
  FOR r IN
    SELECT bp.beacon_id, bp.user_id, bp.role, b.user_id AS author_id,
           EXISTS (
             SELECT 1 FROM public.beacon_help_offer o
             WHERE o.beacon_id = bp.beacon_id AND o.user_id = bp.user_id
               AND o.status = 0) AS has_offer
    FROM public.beacon_participant bp
    JOIN public.beacon b ON b.id = bp.beacon_id
    WHERE b.kind = 0
      AND b.status IN (0, 7, 8)
      AND bp.room_access = 3
      AND bp.user_id <> b.user_id
      AND bp.role NOT IN (0, 1)
      AND NOT EXISTS (
        SELECT 1 FROM public.beacon_commitment_event ce
        WHERE ce.beacon_id = bp.beacon_id AND ce.user_id = bp.user_id
          AND ce.kind = 1)
  LOOP
    IF r.has_offer AND r.role <> 6 THEN
      UPDATE public.beacon_participant
      SET room_access = 0, updated_at = now()
      WHERE beacon_id = r.beacon_id AND user_id = r.user_id;
      _offers := _offers + 1;
      CONTINUE;
    END IF;

    IF r.role = 6 THEN
      DELETE FROM public.beacon_participant
      WHERE beacon_id = r.beacon_id AND user_id = r.user_id;
    ELSE
      UPDATE public.beacon_participant
      SET room_access = 0, updated_at = now()
      WHERE beacon_id = r.beacon_id AND user_id = r.user_id;
    END IF;

    SELECT e.id INTO _edge
    FROM public.beacon_forward_edge e
    WHERE e.beacon_id = r.beacon_id AND e.recipient_id = r.user_id
      AND e.cancelled_at IS NULL
    ORDER BY e.created_at DESC, e.id DESC
    LIMIT 1;

    IF _edge IS NULL THEN
      INSERT INTO public.beacon_forward_edge
        (beacon_id, sender_id, recipient_id, contact_sweep_exempt)
      VALUES (r.beacon_id, r.author_id, r.user_id, true)
      RETURNING id INTO _edge;
    ELSE
      UPDATE public.beacon_forward_edge
      SET contact_sweep_exempt = true
      WHERE id = _edge;
    END IF;

    INSERT INTO public.beacon_author_invite
      (beacon_id, inviter_id, invitee_id, source_post_id,
       arrival_post_edge_id, warm, forward_edge_id)
    VALUES (r.beacon_id, r.author_id, r.user_id, NULL, NULL, true, _edge);

    -- Removing a participant row also deletes the person's inbox row, so
    -- upsert it from the inbound edges.
    INSERT INTO public.inbox_item
      (user_id, beacon_id, status, forward_count, latest_forward_at)
    SELECT r.user_id, r.beacon_id, 0, count(*), max(e.created_at)
    FROM public.beacon_forward_edge e
    WHERE e.beacon_id = r.beacon_id AND e.recipient_id = r.user_id
    ON CONFLICT (user_id, beacon_id) DO UPDATE SET status = 0;

    _unconfirmed := _unconfirmed + 1;
  END LOOP;

  SELECT string_agg(DISTINCT bp.beacon_id, ', ') INTO _skipped
  FROM public.beacon_participant bp
  JOIN public.beacon b ON b.id = bp.beacon_id
  WHERE b.kind = 0
    AND (b.status NOT IN (0, 7, 8))
    AND bp.room_access = 3
    AND bp.user_id <> b.user_id
    AND bp.role NOT IN (0, 1)
    AND NOT EXISTS (
      SELECT 1 FROM public.beacon_commitment_event ce
      WHERE ce.beacon_id = bp.beacon_id AND ce.user_id = bp.user_id
        AND ce.kind = 1);

  RAISE NOTICE 'repair report - offer without an ack: %', _offers;
  RAISE NOTICE 'repair report - no own confirmation: %', _unconfirmed;
  RAISE NOTICE 'repair report - skipped review/terminal Requests: %',
    coalesce(_skipped, '(none)');
END
$$
''',
]);
