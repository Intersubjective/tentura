part of '_migrations.dart';

// Hasura computed field `beacon.rejected_user_ids`: after a prior attempt to
// change the return type to `text[]` (which Hasura rejects for computed fields),
// this migration restores the original `SETOF text` signature.
//
// The single-element serialization bug (bare string instead of JSON array) is
// handled client-side — see WORKAROUNDS.md § 5.
final m0018 = Migration('0018', [
  r'''
DROP FUNCTION IF EXISTS public.beacon_get_rejected_user_ids(public.beacon, json);
''',
  r'''
CREATE OR REPLACE FUNCTION public.beacon_get_rejected_user_ids(
  beacon_row public.beacon,
  hasura_session json
) RETURNS SETOF text
  LANGUAGE sql
  STABLE
  AS $$
SELECT user_id
FROM public.inbox_item
WHERE beacon_id = beacon_row.id AND status = 2;
$$;
''',
]);
// End of migration.
