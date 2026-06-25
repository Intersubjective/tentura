part of '_migrations.dart';

/// m0097 renamed beacon.state → status; this function was still referencing state.
final m0102 = Migration('0102', [
  r'''
CREATE OR REPLACE FUNCTION public.inbox_item_apply_tombstone_after_withdraw(
  p_user_id text,
  p_beacon_id text
) RETURNS void
  LANGUAGE plpgsql
  AS $$
BEGIN
  PERFORM set_config('tentura.allow_inbox_tombstone_transition', '1', true);
  UPDATE public.inbox_item ii
  SET
    status = CASE (SELECT b.status FROM public.beacon b WHERE b.id = p_beacon_id)
      WHEN 2 THEN 4 ELSE 3 END,
    before_response_terminal_at = coalesce(
      ii.before_response_terminal_at,
      now()
    )
  WHERE ii.user_id = p_user_id
    AND ii.beacon_id = p_beacon_id
    AND EXISTS (
      SELECT 1
      FROM public.beacon b
      WHERE b.id = p_beacon_id AND b.status NOT IN (0, 7, 8)
    );
END;
$$;
''',
]);
