part of '_migrations.dart';

/// Detect direct private-graph writes outside their transaction's owner scope
/// when the database session opts into enforcement.
final m0332 = Migration('0332', [
  r'''
CREATE FUNCTION public.assert_owner_scope() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  _owner_id text;
BEGIN
  IF current_setting('tentura.owner_scope_enforce', true) IS DISTINCT FROM 'on'
      OR pg_trigger_depth() <> 1 THEN
    RETURN NEW;
  END IF;

  _owner_id := to_jsonb(NEW) ->> TG_ARGV[0];
  -- A transaction-local setting can read as an empty string after reset.
  IF _owner_id IS NULL OR (
    NULLIF(current_setting('tentura.owner_scopes', true), '')::jsonb
      @> jsonb_build_array(_owner_id)
  ) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Owner scope required for % on %.%',
      TG_OP, TG_TABLE_SCHEMA, TG_TABLE_NAME;
  END IF;

  RETURN NEW;
END;
$$
''',
  for (final entry in const {
    'constellation_anchor': 'viewer_id',
    'constellation_anchor_cursor': 'viewer_id',
    'constellation_anchor_op_log': 'viewer_id',
    'constellation_anchor_target_watermark': 'viewer_id',
    'constellation_layout_snapshot': 'viewer_id',
    'constellation_tag_magnet': 'viewer_id',
    'person_field_first_seen': 'viewer_id',
    'person_tag': 'owner_id',
    'person_tag_member': 'owner_id',
    'person_tag_op_log': 'owner_id',
    'person_tag_revision': 'owner_id',
    'person_tag_suggestion_state': 'owner_id',
    'person_auto_tag_pref': 'owner_id',
  }.entries)
    '''
CREATE TRIGGER assert_owner_scope
BEFORE INSERT OR UPDATE ON public.${entry.key}
FOR EACH ROW EXECUTE FUNCTION public.assert_owner_scope('${entry.value}')
''',
]);
