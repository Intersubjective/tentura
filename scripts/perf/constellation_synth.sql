-- Synthetic dense trust/discoverable data for Constellation perf runs (issue #235).
-- Run ONLY against a disposable copy, e.g. tentura_perfsynth cloned from tentura_devcopy:
--   docker exec -i postgres psql -U postgres -d tentura_perfsynth -f - < scripts/perf/constellation_synth.sql
-- Then load MeritRank: SELECT mr_reset(); SELECT meritrank_init();
-- Dataset-specific ids: the heavy viewer U66728b9dba8d and the template Request
-- B99b6b6bf9cb7 come from the 2026-10-06 dev snapshot; adjust them for another base.
\set ON_ERROR_STOP on
SELECT setseed(0.235);
-- 3000 synthetic users in 3 clusters of 1000
INSERT INTO public."user"(id, display_name, public_key)
SELECT 'Uf' || lpad(n::text, 11, '0'), 'Synth ' || n, 'synthkey' || n
FROM generate_series(1, 3000) n
ON CONFLICT DO NOTHING;
-- ~30 reciprocal trust edges per user inside its cluster
CREATE TEMP TABLE synth_pairs AS
SELECT DISTINCT 'Uf' || lpad(i::text, 11, '0') AS a,
       'Uf' || lpad((((i - 1) / 1000) * 1000 + 1 + floor(random() * 1000))::int::text, 11, '0') AS b
FROM generate_series(1, 3000) i, generate_series(1, 15) k;
DELETE FROM synth_pairs WHERE a = b;
-- the QA-loginable heavy viewer joins cluster 0 with 50 reciprocal edges
INSERT INTO synth_pairs
SELECT 'U66728b9dba8d', 'Uf' || lpad((1 + floor(random() * 1000))::int::text, 11, '0')
FROM generate_series(1, 50);
INSERT INTO user_trust_edge(subject, object, trust_w, target_w)
SELECT a, b, 1, 1 FROM synth_pairs
UNION
SELECT b, a, 1, 1 FROM synth_pairs
ON CONFLICT DO NOTHING;
-- discoverable Requests cloned from a readable template: 10 per cluster-0 user, 2 per other user
DO $$
DECLARE cols text;
BEGIN
  SELECT string_agg(quote_ident(column_name), ', ' ORDER BY ordinal_position) INTO cols
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'beacon'
    AND column_name NOT IN ('id', 'user_id', 'title', 'created_at', 'updated_at')
    AND is_generated = 'NEVER';
  EXECUTE format($f$
    INSERT INTO beacon (id, user_id, title, %1$s)
    SELECT 'Bf' || lpad(((u - 1) * 10 + k)::text, 11, '0'),
           'Uf' || lpad(u::text, 11, '0'),
           'Synthetic request ' || u || '-' || k,
           %2$s
    FROM beacon t, generate_series(1, 3000) u, generate_series(1, 10) k
    WHERE t.id = 'B99b6b6bf9cb7' AND (u <= 1000 OR k <= 2)
  $f$, cols, (SELECT string_agg('t.' || quote_ident(column_name), ', ' ORDER BY ordinal_position)
              FROM information_schema.columns
              WHERE table_schema = 'public' AND table_name = 'beacon'
                AND column_name NOT IN ('id', 'user_id', 'title', 'created_at', 'updated_at')
                AND is_generated = 'NEVER'));
END $$;
SELECT (SELECT count(*) FROM public."user" WHERE id LIKE 'Uf%') AS synth_users,
       (SELECT count(*) FROM user_trust_edge WHERE subject LIKE 'Uf%' OR object LIKE 'Uf%') AS synth_edges,
       (SELECT count(*) FROM beacon WHERE id LIKE 'Bf%') AS synth_beacons;
