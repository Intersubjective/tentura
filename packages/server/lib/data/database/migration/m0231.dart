part of '_migrations.dart';

/// Set-based constellation trust edges and one-round-trip anchor batch
/// writes (#235 U13 part 3/3, `applyBatch` perf budgets).
///
/// `block_hides` is a scalar SQL function whose body has sublinks, so the
/// planner never inlines it: `constellation_trust_edges` paid one function
/// call (~20 µs) per candidate node and per edge — ~20 ms for the ~1,000
/// visible nodes of the dense fixture. The same predicate (a block in either
/// direction, viewer↔node and peer↔peer) is now an anti-join; the result set
/// is unchanged.
///
/// `constellation_anchor_apply_ops` performs the accepted anchor writes of one
/// `applyBatch` call in input order inside the server, then its target
/// watermarks and op-log rows as two set-based inserts, replacing ~4 client
/// round trips per operation under the cursor lock. The caller has already
/// locked the viewer cursor, decided every operation and predicted each
/// resulting revision (the cursor advances by exactly one per accepted
/// write); a final cursor revision other than the predicted one aborts the
/// batch rather than recording wrong results.
final m0231 = Migration('0231', [
  r'''
CREATE OR REPLACE FUNCTION public.constellation_trust_edges(p_viewer_id text, p_ctx text, node_ids text[]) RETURNS TABLE(src text, dst text, tier smallint)
    LANGUAGE sql STABLE
    AS $$
WITH viewer AS (
  SELECT nullif(trim(coalesce(p_viewer_id, '')), '') AS id, coalesce(p_ctx, '') AS ctx
),
visible AS (
  SELECT unnest(public.person_visible_peer_ids_tx(v.id, v.ctx)) AS id   -- D14, symmetric
  FROM viewer v
  WHERE v.id IS NOT NULL
),
-- block_hides(viewer, n) as one set: a block in either direction (m0135).
viewer_blocked AS (
  SELECT ub.blocked_id AS id
  FROM viewer v
  INNER JOIN public.user_block ub ON ub.blocker_id = v.id
  UNION
  SELECT ub.blocker_id
  FROM viewer v
  INNER JOIN public.user_block ub ON ub.blocked_id = v.id
),
allowed AS (
  SELECT DISTINCT n AS id
  FROM viewer v
  CROSS JOIN unnest(node_ids) AS n
  WHERE v.id IS NOT NULL
    AND nullif(trim(coalesce(n, '')), '') IS NOT NULL
    AND (n = v.id OR n IN (SELECT id FROM visible))          -- D6
    AND n NOT IN (SELECT id FROM viewer_blocked)
),
t1 AS (
  SELECT vu.subject::text AS src, vu.object::text AS dst
  FROM public.vote_user vu
  INNER JOIN allowed a ON a.id = vu.subject
  INNER JOIN allowed b ON b.id = vu.object
  WHERE vu.amount > 0 AND vu.subject <> vu.object
    -- peer↔peer block, not just viewer, in either direction
    AND NOT EXISTS (
      SELECT 1 FROM public.user_block ub
      WHERE ub.blocker_id = vu.subject AND ub.blocked_id = vu.object)
    AND NOT EXISTS (
      SELECT 1 FROM public.user_block ub
      WHERE ub.blocker_id = vu.object AND ub.blocked_id = vu.subject)
),
t2 AS (
  SELECT e.subject::text AS src, e.object::text AS dst
  FROM public.user_trust_edge e
  INNER JOIN allowed a ON a.id = e.subject
  INNER JOIN allowed b ON b.id = e.object
  WHERE e.prev_sent_weight > 0 AND e.subject <> e.object     -- positive_only, hard-coded
    AND NOT EXISTS (
      SELECT 1 FROM public.user_block ub
      WHERE ub.blocker_id = e.subject AND ub.blocked_id = e.object)
    AND NOT EXISTS (
      SELECT 1 FROM public.user_block ub
      WHERE ub.blocker_id = e.object AND ub.blocked_id = e.subject)
)
SELECT t1.src, t1.dst, 1::smallint FROM t1
UNION ALL
SELECT t2.src, t2.dst, 2::smallint FROM t2
WHERE NOT EXISTS (SELECT 1 FROM t1 WHERE t1.src = t2.src AND t1.dst = t2.dst);
$$
''',

  r'''
CREATE FUNCTION public.constellation_anchor_apply_ops(
    p_viewer_id text,
    p_write boolean[],
    p_delete boolean[],
    p_target_kinds text[],
    p_target_ids text[],
    p_anchor_ids text[],
    p_x double precision[],
    p_y double precision[],
    p_coordinate_space_versions integer[],
    p_client_op_ids text[],
    p_fingerprints text[],
    p_results jsonb[],
    p_revisions bigint[]
) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  _n integer := coalesce(cardinality(p_client_op_ids), 0);
  _expected bigint;
  _revision bigint;
BEGIN
  IF _n = 0 THEN
    RETURN;
  END IF;
  -- Anchor writes in input order: the revision trigger advances the locked
  -- cursor by one per row, as the caller predicted.
  FOR i IN 1.._n LOOP
    CONTINUE WHEN NOT p_write[i];
    -- Target kinds are the wire values stored in the watermark table.
    IF p_target_kinds[i] = 'PERSON' THEN
      IF p_delete[i] THEN
        DELETE FROM public.constellation_anchor
        WHERE viewer_id = p_viewer_id AND person_id = p_target_ids[i];
      ELSE
        UPDATE public.constellation_anchor
        SET x_units = p_x[i],
            y_units = p_y[i],
            coordinate_space_version = p_coordinate_space_versions[i]
        WHERE viewer_id = p_viewer_id AND person_id = p_target_ids[i];
      END IF;
    ELSE
      IF p_delete[i] THEN
        DELETE FROM public.constellation_anchor
        WHERE viewer_id = p_viewer_id AND beacon_id = p_target_ids[i];
      ELSE
        UPDATE public.constellation_anchor
        SET x_units = p_x[i],
            y_units = p_y[i],
            coordinate_space_version = p_coordinate_space_versions[i]
        WHERE viewer_id = p_viewer_id AND beacon_id = p_target_ids[i];
      END IF;
    END IF;
    IF NOT FOUND THEN
      IF p_delete[i] THEN
        -- Deleting a missing anchor still advances the cursor.
        UPDATE public.constellation_anchor_cursor
        SET revision = revision + 1
        WHERE viewer_id = p_viewer_id;
      ELSE
        INSERT INTO public.constellation_anchor (
          id, viewer_id, person_id, beacon_id,
          x_units, y_units, coordinate_space_version, revision, placed_at
        ) VALUES (
          p_anchor_ids[i], p_viewer_id,
          CASE WHEN p_target_kinds[i] = 'PERSON' THEN p_target_ids[i] END,
          CASE WHEN p_target_kinds[i] = 'BEACON' THEN p_target_ids[i] END,
          p_x[i], p_y[i], p_coordinate_space_versions[i], 0,
          'epoch'::timestamptz
        );
      END IF;
    END IF;
  END LOOP;

  -- Every write advanced the cursor exactly once, so the final revision
  -- proves each predicted one; a mismatch aborts rather than recording it.
  _expected := p_revisions[_n];
  SELECT c.revision INTO _revision
  FROM public.constellation_anchor_cursor c
  WHERE c.viewer_id = p_viewer_id;
  IF _revision IS DISTINCT FROM _expected THEN
    RAISE EXCEPTION 'constellation anchor batch revision drift for viewer %: expected %, found %',
      p_viewer_id, _expected, _revision;
  END IF;

  INSERT INTO public.constellation_anchor_target_watermark
    (viewer_id, target_kind, target_id, revision)
  SELECT DISTINCT ON (o.kind, o.id) p_viewer_id, o.kind, o.id, o.revision
  FROM unnest(p_write, p_target_kinds, p_target_ids, p_revisions)
    AS o(write, kind, id, revision)
  WHERE o.write
  ORDER BY o.kind, o.id, o.revision DESC
  ON CONFLICT (viewer_id, target_kind, target_id)
  DO UPDATE SET revision = EXCLUDED.revision;

  INSERT INTO public.constellation_anchor_op_log
    (viewer_id, client_op_id, fingerprint, result, revision)
  SELECT p_viewer_id, o.client_op_id, decode(o.fingerprint, 'hex'), o.result,
         o.revision
  FROM unnest(p_client_op_ids, p_fingerprints, p_results, p_revisions)
    AS o(client_op_id, fingerprint, result, revision);
END;
$$
''',
]);
