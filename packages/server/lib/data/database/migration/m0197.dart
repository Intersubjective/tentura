part of '_migrations.dart';

/// Recognises `beacon_steward` rows in `beacon_can_read_involvement`.
///
/// `beacon_can_read_content` already admits a steward through an `EXISTS` on
/// `beacon_steward`, but the involvement predicate only accepted stewards as
/// `beacon_participant` rows with `role = 1`. `setBeaconSteward` writes
/// `beacon_steward` and only updates a participant row that already exists, so
/// a steward without one could read the Request yet was refused involvement
/// ("Viewer cannot read request involvement"). Adding the `beacon_steward`
/// branch here keeps the two predicates in agreement for every caller (API
/// guard and Hasura permissions alike), including legacy steward-only rows.
final m0197 = Migration('0197', [
  r'''
CREATE OR REPLACE FUNCTION public.beacon_can_read_involvement(p_beacon_id text, p_viewer_id text) RETURNS boolean
    LANGUAGE sql STABLE
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
      SELECT 1 FROM public.beacon_steward bs
      WHERE bs.beacon_id = p_beacon_id AND bs.user_id = p_viewer_id
    )
  );
$$
''',
]);
