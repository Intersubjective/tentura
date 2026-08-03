part of '_migrations.dart';

/// Removes cascade_mode 2 ("all descendants, standing ignored, never released")
/// from the design. Only mode 0 (no cascade) and mode 1 (standing-aware,
/// probationary — see docs/plans/user-block-design.md §6.1/§6.3) remain.
/// `block_cascade_candidates` always applies `block_cascade_unattached` now;
/// the `_mode` parameter is kept (call sites/signature unchanged) but only
/// ever receives 0 or 1.
final m0138 = Migration('0138', [
  // Defensive: no live row should have cascade_mode = 2 (dev-only branch, no
  // production data), but normalize before tightening the CHECK so the ALTER
  // never fails on stray rows.
  "UPDATE public.user_block_intent SET cascade_mode = 1 WHERE cascade_mode = 2;",
  r'''
ALTER TABLE public.user_block_intent
  DROP CONSTRAINT user_block_intent_cascade_mode_check;
''',
  r'''
ALTER TABLE public.user_block_intent
  ADD CONSTRAINT user_block_intent_cascade_mode_check CHECK (cascade_mode IN (0, 1));
''',
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
    -- invite subtree
    AND s.uid IS DISTINCT FROM _blocker
    -- descend through deleted (anonymized) nodes unconditionally; the tree
    -- structure survives account deletion even though uid becomes NULL
    AND (s.uid IS NULL
         OR public.block_cascade_unattached(_blocker, _root, s.uid))
)
SELECT s.uid, min(s.depth)::int
FROM sub s
WHERE s.uid IS NOT NULL
  AND s.uid <> _blocker
  AND public.block_cascade_unattached(_blocker, _root, s.uid)
GROUP BY s.uid
ORDER BY 2, 1
LIMIT _limit;
$$;
''',
]);
