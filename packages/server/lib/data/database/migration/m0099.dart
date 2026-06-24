part of '_migrations.dart';

/// Beacon invite provenance + Hasura visibility computed fields (ADR 0008 phase 2).
final m0099 = Migration('0099', [
  r'''
ALTER TABLE public.invitation
  ADD COLUMN IF NOT EXISTS parent_forward_edge_id text
  REFERENCES public.beacon_forward_edge(id) ON DELETE SET NULL;
''',
  r'''
CREATE OR REPLACE FUNCTION public.beacon_get_can_read_content(
  beacon_row public.beacon,
  hasura_session json
) RETURNS boolean
  LANGUAGE sql
  STABLE
  AS $$
SELECT public.beacon_can_read_content(
  beacon_row.id,
  (hasura_session ->> 'x-hasura-user-id')::text
);
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.beacon_get_can_read_involvement(
  beacon_row public.beacon,
  hasura_session json
) RETURNS boolean
  LANGUAGE sql
  STABLE
  AS $$
SELECT public.beacon_can_read_involvement(
  beacon_row.id,
  (hasura_session ->> 'x-hasura-user-id')::text
);
$$;
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
WHERE beacon_id = beacon_row.id
  AND status = 2
  AND public.beacon_can_read_involvement(
    beacon_row.id,
    (hasura_session ->> 'x-hasura-user-id')::text
  );
$$;
''',
]);
