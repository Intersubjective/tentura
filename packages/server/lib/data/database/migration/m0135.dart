part of '_migrations.dart';

/// User blocking: effective block set, declared intent, and the cascade
/// membership predicate. See docs/plans/user-block-design.md §4, §6.
final m0135 = Migration('0135', [
  r'''
CREATE TABLE IF NOT EXISTS public.user_block (
  blocker_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  blocked_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  origin_id  text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT user_block_pkey PRIMARY KEY (blocker_id, blocked_id, origin_id),
  CONSTRAINT user_block__no_self CHECK (blocker_id <> blocked_id)
);
''',
  'CREATE INDEX IF NOT EXISTS user_block_reverse_idx ON public.user_block (blocked_id, blocker_id);',
  'CREATE INDEX IF NOT EXISTS user_block_origin_idx  ON public.user_block (blocker_id, origin_id);',
  r'''
CREATE TABLE IF NOT EXISTS public.user_block_intent (
  blocker_id         text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  blocked_id         text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  cascade_mode       smallint NOT NULL DEFAULT 0 CHECK (cascade_mode IN (0,1,2)),
  cascade_status     smallint NOT NULL DEFAULT 0 CHECK (cascade_status IN (0,1,2,3)),
  cascade_cursor     text,
  cascade_snapshot_at timestamptz,
  materialized_count integer NOT NULL DEFAULT 0,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT user_block_intent_pkey PRIMARY KEY (blocker_id, blocked_id),
  CONSTRAINT user_block_intent__no_self CHECK (blocker_id <> blocked_id)
);
''',
  'CREATE INDEX IF NOT EXISTS user_block_intent_pending_idx ON public.user_block_intent (cascade_status) WHERE cascade_status IN (0,1);',
  // §2.1 — the one predicate every read site calls
  r'''
CREATE OR REPLACE FUNCTION public.block_hides(_a text, _b text)
RETURNS boolean LANGUAGE sql STABLE PARALLEL SAFE AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_block WHERE blocker_id = _a AND blocked_id = _b)
      OR EXISTS (SELECT 1 FROM public.user_block WHERE blocker_id = _b AND blocked_id = _a);
$$;
''',
  // §2.2 — cascade membership
  r'''
CREATE OR REPLACE FUNCTION public.block_cascade_unattached(
  _blocker text, _root text, _candidate text
) RETURNS boolean LANGUAGE sql STABLE PARALLEL SAFE AS $$
  SELECT CASE WHEN _candidate = _blocker THEN false ELSE NOT (
    -- (a) the blocker mutually trusts the candidate themselves
    EXISTS (
      SELECT 1
      FROM public.vote_user m_out
      JOIN public.vote_user m_in
        ON m_in.subject = _candidate AND m_in.object = _blocker
      WHERE m_out.subject = _blocker AND m_out.object = _candidate
        AND m_out.amount > 0 AND m_in.amount > 0)
    -- (b) or someone the blocker mutually trusts vouches for the candidate
    OR EXISTS (
      SELECT 1
      FROM public.vote_user v_out
      JOIN public.vote_user v_in
        ON v_in.subject = v_out.object AND v_in.object = _candidate
      WHERE v_out.subject = _candidate
        AND v_out.amount > 0 AND v_in.amount > 0
        AND v_out.object <> _root
        AND v_out.object <> _blocker
        AND NOT EXISTS (
          SELECT 1 FROM public.user_block ub
          WHERE ub.blocker_id = _blocker AND ub.blocked_id = v_out.object)
        AND EXISTS (
          SELECT 1 FROM public.vote_user b_out
          JOIN public.vote_user b_in
            ON b_in.subject = b_out.object AND b_in.object = _blocker
          WHERE b_out.subject = _blocker AND b_out.object = v_out.object
            AND b_out.amount > 0 AND b_in.amount > 0))
  ) END;
$$;
''',
  // §2.3 — cascade candidate set, guarded descent
  r'''
CREATE OR REPLACE FUNCTION public.block_cascade_candidates(
  _blocker text, _root text, _mode smallint, _max_depth integer, _limit integer
) RETURNS TABLE (user_id text, depth integer)
  LANGUAGE sql STABLE AS $$
WITH RECURSIVE sub AS (
  SELECT g.descendant_node_key AS k, g.descendant_user_id AS uid, 1 AS depth
  FROM public.invite_genealogy g
  WHERE g.ancestor_user_id = _root
  UNION ALL
  SELECT g.descendant_node_key, g.descendant_user_id, s.depth + 1
  FROM public.invite_genealogy g
  JOIN sub s ON g.ancestor_node_key = s.k
  WHERE s.depth < _max_depth
    -- never descend through the blocker: everything below them is their own
    -- invite subtree, in either mode
    AND s.uid IS DISTINCT FROM _blocker
    -- descend through deleted (anonymized) nodes unconditionally; the tree
    -- structure survives account deletion even though uid becomes NULL
    AND (s.uid IS NULL
         OR _mode = 2
         OR public.block_cascade_unattached(_blocker, _root, s.uid))
)
SELECT s.uid, min(s.depth)::int
FROM sub s
WHERE s.uid IS NOT NULL
  AND s.uid <> _blocker
  AND (_mode = 2 OR public.block_cascade_unattached(_blocker, _root, s.uid))
GROUP BY s.uid
ORDER BY 2, 1
LIMIT _limit;
$$;
''',
]);
