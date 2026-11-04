part of '_migrations.dart';

/// Personal Field exclusions. Addressed events invalidate hides at read time;
/// their existing writers do not need to know about this table.
final m0290 = Migration('0290', [
  '''
CREATE TABLE public.field_hidden (
  viewer_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  target_kind smallint NOT NULL CHECK (target_kind >= 0),
  target_id text NOT NULL,
  hidden_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (viewer_id, target_kind, target_id)
)
''',
  r'''
CREATE FUNCTION public.field_hide_is_effective(
  p_viewer text, p_kind integer, p_target text, p_hidden_at timestamptz
) RETURNS boolean LANGUAGE sql STABLE AS $$
SELECT NOT EXISTS (
  SELECT 1 FROM public.beacon_forward_edge e
  WHERE e.beacon_id = p_target AND e.recipient_id = p_viewer
    AND e.created_at > p_hidden_at
)
AND NOT EXISTS (
  SELECT 1 FROM public.beacon_help_offer_admission_event e
  WHERE p_kind = 0 AND e.beacon_id = p_target AND e.offer_user_id = p_viewer
    AND e.action IN (1, 2) AND e.created_at > p_hidden_at
)
AND NOT EXISTS (
  SELECT 1 FROM public.beacon_activity_event e
  WHERE e.beacon_id = p_target AND e.target_user_id = p_viewer
    AND e.type = 18 AND e.created_at > p_hidden_at
)
$$
''',
  r'''
CREATE FUNCTION public.field_item_visible(p_viewer text, p_kind integer, p_target text)
RETURNS boolean LANGUAGE sql STABLE AS $$
SELECT NOT EXISTS (
  SELECT 1 FROM public.field_hidden h
  WHERE h.viewer_id = p_viewer AND h.target_kind = p_kind AND h.target_id = p_target
    AND public.field_hide_is_effective(p_viewer, p_kind, p_target, h.hidden_at)
)
AND NOT EXISTS (
  SELECT 1 FROM public.inbox_item i
  WHERE p_kind = 0 AND i.user_id = p_viewer AND i.beacon_id = p_target
    AND i.status = 2
)
$$
''',
]);
