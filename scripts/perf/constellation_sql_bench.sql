-- Per-unit SQL costs for the Constellation read path (issue #235).
-- Edit the viewers list, then: docker exec -i postgres psql -U postgres -d <db> -f - < scripts/perf/constellation_sql_bench.sql
\set QUIET on
CREATE TEMP TABLE viewers AS SELECT unnest(ARRAY['U4551ffecd7eb','U5d28c5def170','U0ad9d9a55f68','U6351030bf7af']) AS v;
DO $$
DECLARE
  r record; t0 timestamptz; i int; n int; ms numeric; vis text[]; c int; b record; nb int;
BEGIN
  FOR r IN SELECT v FROM viewers LOOP
    -- MR RPC latency: 20 sequential mr_mutual_scores calls
    t0 := clock_timestamp();
    FOR i IN 1..20 LOOP PERFORM count(*) FROM mr_mutual_scores(r.v, ''); END LOOP;
    ms := extract(epoch from clock_timestamp()-t0)*1000/20;
    RAISE NOTICE '% mr_mutual_scores avg % ms', r.v, round(ms,2);
    -- mr_node_score latency
    t0 := clock_timestamp();
    FOR i IN 1..20 LOOP PERFORM mr_node_score(r.v, r.v, ''); END LOOP;
    RAISE NOTICE '% mr_node_score avg % ms', r.v, round(extract(epoch from clock_timestamp()-t0)*1000/20,2);
    -- symmetric visibility
    t0 := clock_timestamp();
    SELECT array_agg(peer_id ORDER BY peer_id) INTO vis FROM person_visible_peers_symmetric(r.v, '');
    RAISE NOTICE '% visible_symmetric V=% in % ms', r.v, coalesce(array_length(vis,1),0), round(extract(epoch from clock_timestamp()-t0)*1000,1);
    -- trust edges over visible set
    t0 := clock_timestamp();
    SELECT count(*) INTO c FROM constellation_trust_edges(r.v, '', coalesce(vis,'{}') || r.v);
    RAISE NOTICE '% trust_edges E=% in % ms', r.v, c, round(extract(epoch from clock_timestamp()-t0)*1000,1);
    -- beacon_can_read_content per call over up to 200 published beacons by others
    t0 := clock_timestamp(); nb := 0; n := 0;
    FOR b IN SELECT id FROM beacon WHERE user_id <> r.v ORDER BY id LIMIT 200 LOOP
      nb := nb + 1;
      IF beacon_can_read_content(b.id, r.v) THEN n := n + 1; END IF;
    END LOOP;
    RAISE NOTICE '% beacon_can_read_content % calls (% readable) avg % ms', r.v, nb, n, round(extract(epoch from clock_timestamp()-t0)*1000/greatest(nb,1),3);
  END LOOP;
END $$;
