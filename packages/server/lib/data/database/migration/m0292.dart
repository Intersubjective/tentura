part of '_migrations.dart';

/// Field hide follow-ups to m0290 (which stays as shipped): a cancelled forward
/// is no addressed event, and a For-you rejection is its own stance, so
/// unhiding can no longer leave a rejected item hidden forever.
final m0292 = Migration('0292', [
  r'''
CREATE OR REPLACE FUNCTION public.field_hide_is_effective(
  p_viewer text, p_kind integer, p_target text, p_hidden_at timestamptz
) RETURNS boolean LANGUAGE sql STABLE AS $$
SELECT NOT EXISTS (
  SELECT 1 FROM public.beacon_forward_edge e
  WHERE e.beacon_id = p_target AND e.recipient_id = p_viewer
    AND e.cancelled_at IS NULL
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
CREATE FUNCTION public.field_item_hidden(p_viewer text, p_kind integer, p_target text)
RETURNS boolean LANGUAGE sql STABLE AS $$
SELECT EXISTS (
  SELECT 1 FROM public.field_hidden h
  WHERE h.viewer_id = p_viewer AND h.target_kind = p_kind AND h.target_id = p_target
    AND public.field_hide_is_effective(p_viewer, p_kind, p_target, h.hidden_at)
)
$$
''',
  r'''
CREATE OR REPLACE FUNCTION public.field_item_visible(p_viewer text, p_kind integer, p_target text)
RETURNS boolean LANGUAGE sql STABLE AS $$
SELECT NOT public.field_item_hidden(p_viewer, p_kind, p_target)
AND NOT EXISTS (
  SELECT 1 FROM public.inbox_item i
  WHERE p_kind = 0 AND i.user_id = p_viewer AND i.beacon_id = p_target
    AND i.status = 2
)
$$
''',
]);
