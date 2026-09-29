part of '_migrations.dart';

/// A1: trust ledger schema (Arch §4.1–§4.3) — replaces the legacy
/// source-edge trust pipeline with an evidence ledger, a projection onto
/// `user_trust_edge(target_w)`, and a publish queue drained out of
/// transaction. Also carries P0.2 forward: `mr_bump_publish_epoch` gains the
/// pgmer2 0.8.1 `mr_sync` barrier (first entry, unchanged from the branch's
/// original m0202).
///
/// Inventory (step 1 of the unit): references to
/// `trust_evidence_event`, `user_trust_source_edge`, `trust_context_config`,
/// `trust_apply_source_evidence`, `trust_resync_source`,
/// `trust_rebuild_effective_*`, `meritrank_edge_tombstone`,
/// `half_life_seconds`:
/// - SQL (dropped or rewritten here): functions
///   `trust_apply_source_evidence(text,text,text,text,double precision)`,
///   `trust_resync_source(text)`,
///   `trust_rebuild_effective_edge(text,text,double precision)`,
///   `trust_rebuild_effective_batch(text,text,integer,double precision)`;
///   tables `trust_evidence_event`, `user_trust_source_edge`,
///   `trust_context_config`, `meritrank_edge_tombstone`; column
///   `trust_policy.half_life_seconds`; rewritten:
///   `trust_edge_on_effective_delete()` (enqueue-only) and
///   `meritrank_init()` (reads `target_w`). No view references them.
/// - Dart callers (handled by later units, fail at runtime until then):
///   A2 — `data/repository/trust_evidence_repository.dart`
///   (`trust_apply_source_evidence`, `trust_rebuild_effective_edge`,
///   `trust_evidence_event`), `data/repository/user_block_repository.dart`
///   (`trust_rebuild_effective_edge`),
///   `data/repository/user_trust_edge_repository.dart`
///   (`trust_resync_source`, `user_trust_source_edge`);
///   A4/A5 — `domain/use_case/trust_maintenance_case.dart`
///   (`meritrank_edge_tombstone` drain, `trust_rebuild_effective_batch`).
final m0202 = Migration('0202', [
  // P0.2: pgmer2 0.8.1 adds `mr_sync`, a barrier that flushes pending MR
  // writes to the MeritRank service. Every publish-epoch bump invalidates
  // witness-window caches, so the sync must happen first.
  r'''
CREATE OR REPLACE FUNCTION public.mr_bump_publish_epoch() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM public.mr_sync();
  UPDATE public.mr_publish_epoch SET epoch = epoch + 1 WHERE id = true;
END;
$$
''',

  // Step 2: evidence kinds (phase A: 1-5 and 8; 6-7 arrive with phase B).
  r'''
CREATE TABLE public.trust_kind_config (
    kind smallint NOT NULL,
    slug text NOT NULL,
    polarity smallint NOT NULL,
    half_life_s double precision,
    k_sat double precision NOT NULL,
    mix_weight double precision NOT NULL,
    wall_levels jsonb,
    linear_window_s double precision,
    counts_for_immunity boolean DEFAULT true NOT NULL,
    CONSTRAINT trust_kind_config_pkey PRIMARY KEY (kind),
    CONSTRAINT trust_kind_config_slug_key UNIQUE (slug),
    CONSTRAINT trust_kind_config_polarity_check CHECK ((polarity = ANY (ARRAY[0, 1]))),
    CONSTRAINT trust_kind_config_half_life_s_check CHECK ((half_life_s IS NULL OR half_life_s > (0)::double precision)),
    CONSTRAINT trust_kind_config_k_sat_check CHECK ((k_sat > (0)::double precision)),
    CONSTRAINT trust_kind_config_mix_weight_check CHECK ((mix_weight >= (0)::double precision)),
    CONSTRAINT trust_kind_config_linear_window_s_check CHECK ((linear_window_s IS NULL OR linear_window_s > (0)::double precision))
)
''',
  r'''
INSERT INTO public.trust_kind_config
    (kind, slug, polarity, half_life_s, k_sat, mix_weight, linear_window_s, counts_for_immunity)
VALUES
    (1, 'vouch', 0, NULL, 1, 1.0, NULL, true),
    (2, 'helped', 0, 31536000, 1, 1.0, NULL, true),
    (3, 'marked', 0, 31536000, 0.5, 0.2, NULL, true),
    (4, 'routed', 0, 15724800, 1, 0.5, NULL, true),
    (5, 'useful_forward', 0, 15724800, 2, 0.5, NULL, true),
    (8, 'worked_with_author', 0, NULL, 1, 0.08, 15552000, false)
''',

  // Step 3: the evidence ledger.
  r'''
CREATE TABLE public.trust_evidence (
    id text NOT NULL,
    subject_user_id text NOT NULL,
    object_user_id text NOT NULL,
    kind smallint NOT NULL,
    count double precision NOT NULL,
    source_key text NOT NULL,
    beacon_id text,
    closure_epoch integer,
    related_user_id text,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL,
    retracted_at timestamp with time zone,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT trust_evidence_pkey PRIMARY KEY (id),
    CONSTRAINT trust_evidence_source_key_key UNIQUE (source_key),
    CONSTRAINT trust_evidence_kind_fkey FOREIGN KEY (kind) REFERENCES public.trust_kind_config(kind),
    CONSTRAINT trust_evidence_subject_fkey FOREIGN KEY (subject_user_id) REFERENCES public."user"(id) ON DELETE CASCADE,
    CONSTRAINT trust_evidence_object_fkey FOREIGN KEY (object_user_id) REFERENCES public."user"(id) ON DELETE CASCADE,
    CONSTRAINT trust_evidence_count_check CHECK ((count > (0)::double precision AND count <= ('1000000'::numeric)::double precision)),
    CONSTRAINT trust_evidence_no_self_check CHECK ((subject_user_id <> object_user_id))
)
''',
  r'''
CREATE INDEX trust_evidence_pair_live ON public.trust_evidence USING btree (subject_user_id, object_user_id) WHERE (retracted_at IS NULL)
''',
  r'''
CREATE INDEX trust_evidence_object ON public.trust_evidence USING btree (object_user_id)
''',
  r'''
CREATE INDEX trust_evidence_kind_dedup ON public.trust_evidence USING btree (kind, subject_user_id, object_user_id, occurred_at) WHERE (retracted_at IS NULL)
''',
  r'''
CREATE INDEX trust_evidence_episode ON public.trust_evidence USING btree (beacon_id, closure_epoch)
''',

  // Step 4: publication queue and the single-publisher fencing lease.
  r'''
CREATE TABLE public.trust_publish_queue (
    subject_user_id text NOT NULL,
    object_user_id text NOT NULL,
    enqueued_at timestamp with time zone DEFAULT now() NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    next_attempt_at timestamp with time zone DEFAULT now() NOT NULL,
    last_error text,
    CONSTRAINT trust_publish_queue_pkey PRIMARY KEY (subject_user_id, object_user_id)
)
''',
  r'''
CREATE TABLE public.trust_publisher_lease (
    id smallint NOT NULL,
    owner text,
    token bigint DEFAULT 0 NOT NULL,
    lease_until timestamp with time zone DEFAULT 'epoch'::timestamp with time zone NOT NULL,
    CONSTRAINT trust_publisher_lease_pkey PRIMARY KEY (id),
    CONSTRAINT trust_publisher_lease_id_check CHECK ((id = 1))
)
''',
  r'''
INSERT INTO public.trust_publisher_lease (id) VALUES (1)
''',

  // Step 5: cutover marker (phase A leaves it 'pending').
  r'''
CREATE TABLE public.trust_cutover_state (
    id smallint NOT NULL,
    status text NOT NULL,
    owner text,
    token bigint DEFAULT 0 NOT NULL,
    lease_until timestamp with time zone DEFAULT 'epoch'::timestamp with time zone NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT trust_cutover_state_pkey PRIMARY KEY (id),
    CONSTRAINT trust_cutover_state_id_check CHECK ((id = 1)),
    CONSTRAINT trust_cutover_state_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'done'::text])))
)
''',
  r'''
INSERT INTO public.trust_cutover_state (id, status) VALUES (1, 'pending')
''',

  // Step 6: runtime config (walls stay disabled in phase A).
  r'''
CREATE TABLE public.trust_config (
    key text NOT NULL,
    value jsonb NOT NULL,
    CONSTRAINT trust_config_pkey PRIMARY KEY (key)
)
''',
  r'''
INSERT INTO public.trust_config (key, value) VALUES
    ('wall_publish_enabled', 'false'),
    ('epsilon', '0.1')
''',

  // Step 7: legacy edges are not portable to the ledger — wipe them with the
  // delete trigger disabled so the wipe does not flood the publish queue.
  r'''
ALTER TABLE public.user_trust_edge DISABLE TRIGGER trust_edge_effective_delete_mr
''',
  r'''
DELETE FROM public.user_trust_edge
''',
  r'''
ALTER TABLE public.user_trust_edge ENABLE TRIGGER trust_edge_effective_delete_mr
''',

  // Step 8: deletion enqueues publication instead of calling MR in
  // transaction. The trigger itself (incl. its
  // WHEN (old.prev_sent_weight <> 0) condition) is kept.
  r'''
CREATE OR REPLACE FUNCTION public.trust_edge_on_effective_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF OLD.prev_sent_weight <> 0 THEN
    INSERT INTO public.trust_publish_queue (subject_user_id, object_user_id)
    VALUES (OLD.subject, OLD.object)
    ON CONFLICT (subject_user_id, object_user_id)
      DO UPDATE SET next_attempt_at = now();
  END IF;
  RETURN OLD;
END;
$$
''',

  // Step 9: the queue is the only publication path; the tombstone table and
  // its (Dart-side, A4/A5) drain path go away.
  r'''
DROP TABLE IF EXISTS public.meritrank_edge_tombstone
''',

  // Step 10: the edge row keeps subject/object/prev_sent_weight and gains the
  // projection columns.
  r'''
ALTER TABLE public.user_trust_edge
    DROP COLUMN s_very_bad,
    DROP COLUMN s_bad,
    DROP COLUMN s_no_effect,
    DROP COLUMN s_good,
    DROP COLUMN s_very_good,
    DROP COLUMN anchor_at,
    ADD COLUMN trust_w double precision DEFAULT 0 NOT NULL,
    ADD COLUMN wall_d double precision DEFAULT 0 NOT NULL,
    ADD COLUMN target_w double precision DEFAULT 0 NOT NULL
''',

  // Step 11: legacy source-edge pipeline.
  r'''
DROP FUNCTION IF EXISTS public.trust_apply_source_evidence(text, text, text, text, double precision)
''',
  r'''
DROP FUNCTION IF EXISTS public.trust_resync_source(text)
''',
  r'''
DROP FUNCTION IF EXISTS public.trust_rebuild_effective_edge(text, text, double precision)
''',
  r'''
DROP FUNCTION IF EXISTS public.trust_rebuild_effective_batch(text, text, integer, double precision)
''',
  r'''
DROP TABLE IF EXISTS public.trust_evidence_event
''',
  r'''
DROP TABLE IF EXISTS public.user_trust_source_edge
''',
  r'''
DROP TABLE IF EXISTS public.trust_context_config
''',
  r'''
ALTER TABLE public.trust_policy DROP COLUMN IF EXISTS half_life_seconds
''',

  // Step 12: fold live evidence of one pair into trust values (Arch §4.2).
  // Saturation is per kind: s_k is the decayed count sum over live rows of
  // kind k, and each kind contributes mix_k * s_k / (k_k + s_k). Vouch is
  // read from vote_user (amount > 0 => s = 1) and contributes 1.0*s/(1+s).
  r'''
CREATE FUNCTION public.trust_fold_pair(p_subject text, p_object text) RETURNS TABLE(trust_w double precision, trust_recent double precision, n_noisy double precision)
    LANGUAGE sql STABLE
    AS $$
WITH live AS (
  SELECT
    e.kind,
    e.count AS cnt,
    extract(epoch FROM (now() - e.occurred_at)) AS age,
    c.polarity,
    c.k_sat,
    c.mix_weight,
    c.counts_for_immunity,
    CASE
      WHEN c.linear_window_s IS NOT NULL
        THEN greatest(0, 1 - extract(epoch FROM (now() - e.occurred_at)) / c.linear_window_s)
      WHEN c.half_life_s IS NOT NULL
        THEN power(2, -extract(epoch FROM (now() - e.occurred_at)) / c.half_life_s)
      ELSE 1
    END AS decay
  FROM public.trust_evidence e
  JOIN public.trust_kind_config c ON c.kind = e.kind
  WHERE e.subject_user_id = p_subject
    AND e.object_user_id = p_object
    AND e.retracted_at IS NULL
),
per_kind AS (
  SELECT
    kind,
    polarity,
    k_sat,
    mix_weight,
    counts_for_immunity,
    sum(cnt * decay) AS s_k,
    sum(cnt * decay) FILTER (WHERE age <= 15552000) AS s_k_recent
  FROM live
  GROUP BY kind, polarity, k_sat, mix_weight, counts_for_immunity
),
vouch AS (
  SELECT CASE WHEN EXISTS (
    SELECT 1 FROM public.vote_user
    WHERE subject = p_subject AND object = p_object AND amount > 0
  ) THEN 0.5::double precision ELSE 0::double precision END AS t_vouch
)
SELECT
  coalesce((SELECT sum(p.mix_weight * p.s_k / (p.k_sat + p.s_k))
            FROM per_kind p WHERE p.polarity = 0), 0)
    + (SELECT t_vouch FROM vouch),
  coalesce((SELECT sum(p.mix_weight * p.s_k_recent / (p.k_sat + p.s_k_recent))
            FROM per_kind p WHERE p.counts_for_immunity), 0)
    + (SELECT t_vouch FROM vouch),
  coalesce((SELECT sum(p.s_k) FROM per_kind p WHERE p.kind = 7), 0)
$$
''',

  // Step 13: project one pair onto user_trust_edge and enqueue publication
  // when the target materially changed. Never calls MR. Phase A: no wall
  // branches (wall_publish_enabled = false), ban forces target 0.
  r'''
CREATE FUNCTION public.trust_project_pair(p_subject text, p_object text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  _t double precision;
  _recent double precision;
  _noisy double precision;
  _eps double precision;
  _target double precision;
  _prev double precision;
BEGIN
  PERFORM public.trust_pair_lock(p_subject, p_object);

  SELECT f.trust_w, f.trust_recent, f.n_noisy
    INTO _t, _recent, _noisy
    FROM public.trust_fold_pair(p_subject, p_object) f;

  SELECT (c.value)::text::double precision INTO _eps
    FROM public.trust_config c WHERE c.key = 'epsilon';
  _eps := coalesce(_eps, 0.1);

  _target := CASE
    WHEN EXISTS (SELECT 1 FROM public.user_block
                 WHERE blocker_id = p_subject AND blocked_id = p_object)
    THEN 0
    WHEN _t > 0 THEN _t
    ELSE 0
  END;

  INSERT INTO public.user_trust_edge (subject, object, trust_w, wall_d, target_w)
  VALUES (p_subject, p_object, _t, 0, _target)
  ON CONFLICT (subject, object) DO UPDATE SET
    trust_w = EXCLUDED.trust_w,
    wall_d = EXCLUDED.wall_d,
    target_w = EXCLUDED.target_w,
    updated_at = now()
  RETURNING prev_sent_weight INTO _prev;
  _prev := coalesce(_prev, 0);

  IF _target = 0 AND _prev = 0 THEN
    DELETE FROM public.user_trust_edge
    WHERE subject = p_subject AND object = p_object;
  END IF;

  IF abs(_target - _prev) > _eps OR sign(_target) <> sign(_prev) THEN
    INSERT INTO public.trust_publish_queue (subject_user_id, object_user_id)
    VALUES (p_subject, p_object)
    ON CONFLICT (subject_user_id, object_user_id)
      DO UPDATE SET next_attempt_at = now();
  END IF;
END;
$$
''',

  // Step 14: initial MR load reads the projection target (only pairs that
  // should be published); polling branches are unchanged from m0193.
  r'''
CREATE OR REPLACE FUNCTION public.meritrank_init() RETURNS integer
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  _meritrank_new_edges_enabled constant boolean := false;
  _src text[];
  _dst text[];
  _weight float8[];
  _magnitude bigint[];
  _context text[];
  _total integer := 0;
  _edge_count integer;
BEGIN
  WITH all_edges AS (
    SELECT subject AS src, object AS dst, target_w AS weight, 0::bigint AS magnitude, ''::text AS context FROM user_trust_edge WHERE target_w <> 0
    UNION ALL
    SELECT pv.id, p.id, 1.0::float8, 0::bigint, ''::text FROM polling p JOIN polling_variant pv ON p.id = pv.polling_id WHERE p.enabled = true
    UNION ALL
    SELECT pa.author_id, pa.polling_variant_id, 1.0::float8, 0::bigint, ''::text FROM polling_act pa JOIN polling p ON p.id = pa.polling_id WHERE p.enabled = true
  ),
  agg AS (
    SELECT
      coalesce(array_agg(src), ARRAY[]::text[]) AS src_arr,
      coalesce(array_agg(dst), ARRAY[]::text[]) AS dst_arr,
      coalesce(array_agg(weight), ARRAY[]::float8[]) AS weight_arr,
      coalesce(array_agg(magnitude), ARRAY[]::bigint[]) AS magnitude_arr,
      coalesce(array_agg(context), ARRAY[]::text[]) AS context_arr,
      count(*)::int AS cnt
    FROM all_edges
  )
  SELECT src_arr, dst_arr, weight_arr, magnitude_arr, context_arr, cnt
  INTO _src, _dst, _weight, _magnitude, _context, _edge_count
  FROM agg;

  _total := _total + _edge_count;
  PERFORM mr_bulk_load_edges(_src, _dst, _weight, _magnitude, _context, 120000::bigint);

  IF _meritrank_new_edges_enabled THEN
    SELECT _total + count(*)::int INTO _total FROM (SELECT mr_set_new_edges_filter(user_id, filter) FROM user_updates) AS _;
  END IF;

  RETURN _total;
END;
$$
''',
]);
