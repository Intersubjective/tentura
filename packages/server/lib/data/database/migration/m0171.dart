part of '_migrations.dart';

/// Issue #146 T08+T09: `beacon_ancestor` closure table, hierarchy context
/// grants in `beacon_can_read_content` / `beacon_access_reasons`, and a
/// temporary `beacon_can_read_linked_detail` alias (removed in T10).
final m0171 = Migration('0171', [
  r'''
CREATE TABLE IF NOT EXISTS public.beacon_ancestor (
  beacon_id   text    NOT NULL REFERENCES public.beacon(id) ON DELETE CASCADE,
  ancestor_id text    NOT NULL REFERENCES public.beacon(id) ON DELETE CASCADE,
  depth       integer NOT NULL CHECK (depth >= 1),
  CONSTRAINT beacon_ancestor_pkey PRIMARY KEY (beacon_id, ancestor_id)
);
''',
  r'''
CREATE INDEX IF NOT EXISTS beacon_ancestor_ancestor_idx
  ON public.beacon_ancestor (ancestor_id);
''',
  r'''
CREATE INDEX IF NOT EXISTS beacon_parent_beacon_id_idx
  ON public.beacon (parent_beacon_id) WHERE parent_beacon_id IS NOT NULL;
''',
  r'''
REVOKE ALL ON TABLE public.beacon_ancestor FROM PUBLIC;
''',
  r'''
CREATE OR REPLACE FUNCTION public.beacon_ancestor_on_insert()
RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  IF NEW.parent_beacon_id IS NULL THEN
    RETURN NEW;
  END IF;
  INSERT INTO public.beacon_ancestor (beacon_id, ancestor_id, depth)
  SELECT NEW.id, NEW.parent_beacon_id, 1
  UNION ALL
  SELECT NEW.id, a.ancestor_id, a.depth + 1
  FROM public.beacon_ancestor a
  WHERE a.beacon_id = NEW.parent_beacon_id
  ON CONFLICT DO NOTHING;
  RETURN NEW;
END;
$$;
''',
  r'''
DROP TRIGGER IF EXISTS beacon_ancestor_on_insert_trg ON public.beacon;
''',
  r'''
CREATE TRIGGER beacon_ancestor_on_insert_trg
  AFTER INSERT ON public.beacon
  FOR EACH ROW
  EXECUTE FUNCTION public.beacon_ancestor_on_insert();
''',
  r'''
WITH RECURSIVE chain AS (
  SELECT b.id AS beacon_id, b.parent_beacon_id AS ancestor_id, 1 AS depth
  FROM public.beacon b
  WHERE b.parent_beacon_id IS NOT NULL
  UNION ALL
  SELECT c.beacon_id, p.parent_beacon_id, c.depth + 1
  FROM chain c
  JOIN public.beacon p ON p.id = c.ancestor_id
  WHERE p.parent_beacon_id IS NOT NULL
)
INSERT INTO public.beacon_ancestor (beacon_id, ancestor_id, depth)
SELECT beacon_id, ancestor_id, depth FROM chain
ON CONFLICT DO NOTHING;
''',
  r'''
-- STABLE preserves statement-snapshot semantics. PL/pgSQL caches the query
-- plan across per-row calls; it does not cache membership or access results.
CREATE OR REPLACE FUNCTION public.beacon_can_read_content(
  p_beacon_id text,
  p_viewer_id text
) RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  AS $$
BEGIN
RETURN COALESCE((
  SELECT CASE
    WHEN public.block_hides(b.user_id, p_viewer_id) THEN false
    WHEN b.status = 3 THEN b.user_id = p_viewer_id
    WHEN b.status = 2 THEN false
    WHEN b.user_id = p_viewer_id THEN true
    WHEN EXISTS (
      SELECT 1 FROM public.beacon_forward_edge fe
      WHERE fe.beacon_id = p_beacon_id
        AND fe.recipient_id = p_viewer_id
        AND fe.cancelled_at IS NULL
    ) THEN true
    WHEN EXISTS (
      SELECT 1 FROM public.beacon_participant bp
      WHERE bp.beacon_id = p_beacon_id
        AND bp.user_id = p_viewer_id
        AND (bp.role = 1 OR bp.room_access = 3)
    ) THEN true
    WHEN EXISTS (
      SELECT 1 FROM public.beacon_help_offer ho
      WHERE ho.beacon_id = p_beacon_id
        AND ho.user_id = p_viewer_id
        AND ho.status = 0
    ) THEN true
    WHEN b.is_discoverable
      AND b.status IN (0, 7, 8)
      AND b.published_at IS NOT NULL
      AND b.user_id IS NOT NULL
      AND public.person_are_mutually_visible_cached(p_viewer_id, b.user_id, '')
      THEN true
    WHEN EXISTS (
      SELECT 1 FROM public.beacon_steward bs
      WHERE bs.beacon_id = p_beacon_id AND bs.user_id = p_viewer_id
    ) THEN true
    -- These bounded probes mirror beacon_member in m0170 exactly. Keep both
    -- functions in sync with that canonical view: published, non-draft/deleted;
    -- author OR unblocked steward/participant (role = 1 OR room_access = 3).
    -- The view's author branch intentionally has no block_hides predicate.
    -- CASE checks blocks only for actual non-author members, not every descendant.
    -- contextChild: member of the immediate parent (D1)
    WHEN b.parent_beacon_id IS NOT NULL
      AND b.published_at IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.beacon member_beacon
        WHERE member_beacon.id = b.parent_beacon_id
          AND member_beacon.status NOT IN (2, 3)
          AND member_beacon.published_at IS NOT NULL
          AND (
            (member_beacon.user_id IS NOT NULL
              AND member_beacon.user_id = p_viewer_id)
            OR CASE WHEN
              EXISTS (
                SELECT 1 FROM public.beacon_steward bs
                WHERE bs.beacon_id = member_beacon.id
                  AND bs.user_id = p_viewer_id
              )
              OR EXISTS (
                SELECT 1 FROM public.beacon_participant bp
                WHERE bp.beacon_id = member_beacon.id
                  AND bp.user_id = p_viewer_id
                  AND (bp.role = 1 OR bp.room_access = 3)
              )
              THEN NOT public.block_hides(member_beacon.user_id, p_viewer_id)
              ELSE false
            END
          )
      ) THEN true
    -- contextAncestor: member of some descendant (D1)
    WHEN b.published_at IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.beacon_ancestor a
        JOIN public.beacon member_beacon ON member_beacon.id = a.beacon_id
        WHERE a.ancestor_id = b.id
          AND member_beacon.status NOT IN (2, 3)
          AND member_beacon.published_at IS NOT NULL
          AND (
            (member_beacon.user_id IS NOT NULL
              AND member_beacon.user_id = p_viewer_id)
            OR CASE WHEN
              EXISTS (
                SELECT 1 FROM public.beacon_steward bs
                WHERE bs.beacon_id = member_beacon.id
                  AND bs.user_id = p_viewer_id
              )
              OR EXISTS (
                SELECT 1 FROM public.beacon_participant bp
                WHERE bp.beacon_id = member_beacon.id
                  AND bp.user_id = p_viewer_id
                  AND (bp.role = 1 OR bp.room_access = 3)
              )
              THEN NOT public.block_hides(member_beacon.user_id, p_viewer_id)
              ELSE false
            END
          )
      ) THEN true
    ELSE false
  END
  FROM public.beacon b
  WHERE b.id = p_beacon_id
), false);
END;
$$;
''',
  r'''
-- Reuse the query plan for the same reason projections used by Hasura.
CREATE OR REPLACE FUNCTION public.beacon_access_reasons(
  p_beacon_id text,
  p_viewer_id text
) RETURNS integer
  LANGUAGE plpgsql
  STABLE
  AS $$
BEGIN
RETURN COALESCE((
  SELECT CASE
    WHEN nullif(btrim(coalesce(p_viewer_id, '')), '') IS NULL THEN 0
    WHEN public.block_hides(b.user_id, p_viewer_id) THEN 0
    WHEN b.status = 3 THEN CASE WHEN b.user_id = p_viewer_id THEN 1 ELSE 0 END
    WHEN b.status = 2 THEN 0
    ELSE
        (CASE WHEN b.user_id = p_viewer_id THEN 1 ELSE 0 END)
      | (CASE WHEN EXISTS (
            SELECT 1 FROM public.beacon_steward bs
            WHERE bs.beacon_id = b.id AND bs.user_id = p_viewer_id
          ) OR EXISTS (
            SELECT 1 FROM public.beacon_participant bp
            WHERE bp.beacon_id = b.id AND bp.user_id = p_viewer_id AND bp.role = 1
          ) THEN 2 ELSE 0 END)
      | (CASE WHEN EXISTS (
            SELECT 1 FROM public.beacon_participant bp
            WHERE bp.beacon_id = b.id AND bp.user_id = p_viewer_id AND bp.room_access = 3
          ) THEN 4 ELSE 0 END)
      | (CASE WHEN EXISTS (
            SELECT 1 FROM public.beacon_forward_edge fe
            WHERE fe.beacon_id = b.id AND fe.recipient_id = p_viewer_id
              AND fe.cancelled_at IS NULL
          ) THEN 8 ELSE 0 END)
      | (CASE WHEN EXISTS (
            SELECT 1 FROM public.beacon_help_offer ho
            WHERE ho.beacon_id = b.id AND ho.user_id = p_viewer_id AND ho.status = 0
          ) THEN 16 ELSE 0 END)
      | (CASE WHEN b.is_discoverable
            AND b.status IN (0, 7, 8)
            AND b.published_at IS NOT NULL
            AND b.user_id IS NOT NULL
            AND public.person_are_mutually_visible_cached(p_viewer_id, b.user_id, '')
          THEN 32 ELSE 0 END)
      -- Same bounded beacon_member probes as beacon_can_read_content above.
      | (CASE WHEN b.parent_beacon_id IS NOT NULL AND b.published_at IS NOT NULL
            AND EXISTS (
                SELECT 1 FROM public.beacon member_beacon
                WHERE member_beacon.id = b.parent_beacon_id
                  AND member_beacon.status NOT IN (2, 3)
                  AND member_beacon.published_at IS NOT NULL
                  AND (
                    (member_beacon.user_id IS NOT NULL
                      AND member_beacon.user_id = p_viewer_id)
                    OR CASE WHEN
                      EXISTS (
                        SELECT 1 FROM public.beacon_steward bs
                        WHERE bs.beacon_id = member_beacon.id
                          AND bs.user_id = p_viewer_id
                      )
                      OR EXISTS (
                        SELECT 1 FROM public.beacon_participant bp
                        WHERE bp.beacon_id = member_beacon.id
                          AND bp.user_id = p_viewer_id
                          AND (bp.role = 1 OR bp.room_access = 3)
                      )
                      THEN NOT public.block_hides(member_beacon.user_id, p_viewer_id)
                      ELSE false
                    END
                  )
            )
          THEN 64 ELSE 0 END)
      | (CASE WHEN b.published_at IS NOT NULL
            AND EXISTS (
                SELECT 1 FROM public.beacon_ancestor a
                JOIN public.beacon member_beacon ON member_beacon.id = a.beacon_id
                WHERE a.ancestor_id = b.id
                  AND member_beacon.status NOT IN (2, 3)
                  AND member_beacon.published_at IS NOT NULL
                  AND (
                    (member_beacon.user_id IS NOT NULL
                      AND member_beacon.user_id = p_viewer_id)
                    OR CASE WHEN
                      EXISTS (
                        SELECT 1 FROM public.beacon_steward bs
                        WHERE bs.beacon_id = member_beacon.id
                          AND bs.user_id = p_viewer_id
                      )
                      OR EXISTS (
                        SELECT 1 FROM public.beacon_participant bp
                        WHERE bp.beacon_id = member_beacon.id
                          AND bp.user_id = p_viewer_id
                          AND (bp.role = 1 OR bp.room_access = 3)
                      )
                      THEN NOT public.block_hides(member_beacon.user_id, p_viewer_id)
                      ELSE false
                    END
                  )
            )
          THEN 128 ELSE 0 END)
  END
  FROM public.beacon b
  WHERE b.id = p_beacon_id
), 0);
END;
$$;
''',
  r'''
-- Temporary alias; T10 removes every caller and drops it.
CREATE OR REPLACE FUNCTION public.beacon_can_read_linked_detail(
  p_beacon_id text, p_viewer_id text
) RETURNS boolean LANGUAGE sql STABLE AS $$
SELECT public.beacon_can_read_content(p_beacon_id, p_viewer_id);
$$;
''',
]);
