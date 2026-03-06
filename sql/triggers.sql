-- Triggers and trigger functions for MeritRank + app logic
-- Extracted from packages/server migrations m0002, m0003, m0005.
-- Prerequisites: mr_put_edge(), mr_delete_edge(), mr_set_new_edges_filter() must exist
-- (e.g. from MeritRank/Hasura schema). Tables public.beacon, comment, opinion,
-- vote_beacon, vote_comment, vote_user, "user", user_vsids, invitation, message,
-- polling, polling_variant, polling_act, user_updates must exist.
--
-- Usage: psql -U postgres -d your_db -f sql/triggers.sql

-- Helper used by updated_at triggers
CREATE OR REPLACE FUNCTION public.set_current_timestamp_updated_at()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;

-- Trigger functions (before_insert / vsids)
CREATE OR REPLACE FUNCTION public.beacon_before_insert()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  UPDATE user_vsids SET counter = counter + 1
    WHERE user_id = NEW.user_id
    RETURNING counter INTO NEW.ticker;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.comment_before_insert()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  UPDATE user_vsids SET counter = counter + 1
    WHERE user_id = NEW.user_id
    RETURNING counter INTO NEW.ticker;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_meritrank_beacon_mutation()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  IF (TG_OP = 'INSERT') THEN
    PERFORM mr_put_edge(
      NEW.id,
      NEW.user_id,
      1::double precision,
      NEW.context,
      0
    );
    PERFORM mr_put_edge(
      NEW.user_id,
      NEW.id,
      1::double precision,
      NEW.context,
      NEW.ticker
    );
    RETURN NEW;

  ELSIF (TG_OP = 'DELETE') THEN
    PERFORM mr_delete_edge(OLD.id, OLD.user_id, OLD.context);
    PERFORM mr_delete_edge(OLD.user_id, OLD.id, OLD.context);
    RETURN OLD;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_meritrank_comment_mutation()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  context text;
BEGIN
  SELECT beacon.context
    INTO context
    FROM beacon
    WHERE beacon.id = NEW.beacon_id;

  IF (TG_OP = 'INSERT') THEN
    PERFORM mr_put_edge(
      NEW.id,
      NEW.user_id,
      1::double precision,
      context,
      0
    );
    PERFORM mr_put_edge(
      NEW.user_id,
      NEW.id,
      1::double precision,
      context,
      NEW.ticker
    );
    RETURN NEW;

  ELSIF (TG_OP = 'DELETE') THEN
    PERFORM mr_delete_edge(OLD.id, OLD.user_id, context);
    PERFORM mr_delete_edge(OLD.user_id, OLD.id, context);
    RETURN OLD;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_meritrank_opinion_mutation()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  IF (TG_OP = 'INSERT') THEN
    PERFORM mr_put_edge(
      NEW.subject,
      NEW.id,
      (abs(NEW.amount))::double precision,
      '',
      NEW.ticker
    );
    PERFORM mr_put_edge(
      NEW.id,
      NEW.subject,
      (1)::double precision,
      '',
      NEW.ticker
    );
    PERFORM mr_put_edge(
      NEW.id,
      NEW.object,
      (sign(NEW.amount))::double precision,
      '',
      NEW.ticker
    );
    RETURN NEW;

  ELSIF (TG_OP = 'DELETE') THEN
    PERFORM mr_delete_edge(OLD.subject, OLD.id);
    PERFORM mr_delete_edge(OLD.id, OLD.subject);
    PERFORM mr_delete_edge(OLD.id, OLD.object);
    RETURN OLD;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_meritrank_vote_beacon_mutation()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  _context text;
BEGIN
  SELECT beacon.context
    INTO STRICT _context
    FROM beacon
    WHERE beacon.id = NEW.object;

  IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
    PERFORM mr_put_edge(
      NEW.subject,
      NEW.object,
      (NEW.amount)::double precision,
      _context,
      NEW.ticker
    );
    RETURN NEW;

  ELSIF (TG_OP = 'DELETE') THEN
    PERFORM mr_delete_edge(
      OLD.subject,
      OLD.object,
      _context
    );
    RETURN OLD;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_meritrank_vote_comment_mutation()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  _context text;
  beacon_id text;
BEGIN
  SELECT comment.beacon_id
    INTO beacon_id
    FROM comment
    WHERE comment.id = NEW.object;

  SELECT beacon.context
    INTO _context
    FROM beacon
    WHERE beacon.id = beacon_id;

  IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
    PERFORM mr_put_edge(
      NEW.subject,
      NEW.object,
      (NEW.amount)::double precision,
      _context,
      NEW.ticker
    );
    RETURN NEW;

  ELSIF (TG_OP = 'DELETE') THEN
    PERFORM mr_delete_edge(
      OLD.subject,
      OLD.object,
      _context
    );
    RETURN OLD;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_meritrank_vote_user_mutation()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
    PERFORM mr_put_edge(
      NEW.subject,
      NEW.object,
      (NEW.amount)::double precision,
      ''::text, NEW.ticker
    );
    RETURN NEW;

  ELSIF (TG_OP = 'DELETE') THEN
    PERFORM mr_delete_edge(
      OLD.subject,
      OLD.object,
      ''::text
    );
    RETURN OLD;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.on_public_user_update()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  IF NEW.has_picture = false THEN
    _new.blur_hash = '';
    _new.pic_height = 0;
    _new.pic_width = 0;
  END IF;
  RETURN _new;
END;
$$;

CREATE OR REPLACE FUNCTION public.on_user_created()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  INSERT INTO user_vsids
    VALUES (NEW.id, DEFAULT, DEFAULT);
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.opinion_before_insert()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  UPDATE user_vsids SET counter = counter + 1
    WHERE user_id = NEW.subject
    RETURNING counter INTO NEW.ticker;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.vote_beacon_before_insert()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  UPDATE user_vsids SET counter = counter + 1
    WHERE user_id = NEW.subject
    RETURNING counter INTO NEW.ticker;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.vote_comment_before_insert()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  UPDATE user_vsids SET counter = counter + 1
    WHERE user_id = NEW.subject
    RETURNING counter INTO NEW.ticker;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.vote_user_before_insert()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  UPDATE user_vsids SET counter = counter + 1
    WHERE user_id = NEW.subject
    RETURNING counter INTO NEW.ticker;
  RETURN NEW;
END;
$$;

-- Triggers
CREATE OR REPLACE TRIGGER notify_meritrank_beacon_mutation
  AFTER INSERT OR DELETE ON public.beacon
  FOR EACH ROW EXECUTE FUNCTION public.notify_meritrank_beacon_mutation();

CREATE OR REPLACE TRIGGER notify_meritrank_comment_mutation
  AFTER INSERT OR DELETE ON public.comment
  FOR EACH ROW EXECUTE FUNCTION public.notify_meritrank_comment_mutation();

CREATE OR REPLACE TRIGGER notify_meritrank_opinion_mutation
  AFTER INSERT OR DELETE ON public.opinion
  FOR EACH ROW EXECUTE FUNCTION public.notify_meritrank_opinion_mutation();

CREATE OR REPLACE TRIGGER notify_meritrank_vote_beacon_mutation
  AFTER INSERT OR UPDATE ON public.vote_beacon
  FOR EACH ROW EXECUTE FUNCTION public.notify_meritrank_vote_beacon_mutation();

CREATE OR REPLACE TRIGGER notify_meritrank_vote_comment_mutation
  AFTER INSERT OR UPDATE ON public.vote_comment
  FOR EACH ROW EXECUTE FUNCTION public.notify_meritrank_vote_comment_mutation();

CREATE OR REPLACE TRIGGER notify_meritrank_vote_user_mutation
  AFTER INSERT OR UPDATE ON public.vote_user
  FOR EACH ROW EXECUTE FUNCTION public.notify_meritrank_vote_user_mutation();

CREATE OR REPLACE TRIGGER on_public_user_update
  BEFORE UPDATE ON public."user"
  FOR EACH ROW EXECUTE FUNCTION public.on_public_user_update();

CREATE OR REPLACE TRIGGER on_user_created
  AFTER INSERT ON public."user"
  FOR EACH ROW EXECUTE FUNCTION public.on_user_created();

CREATE OR REPLACE TRIGGER public_beacon_before_insert
  BEFORE INSERT ON public.beacon
  FOR EACH ROW EXECUTE FUNCTION public.beacon_before_insert();

CREATE OR REPLACE TRIGGER public_comment_before_insert
  BEFORE INSERT ON public.comment
  FOR EACH ROW EXECUTE FUNCTION public.comment_before_insert();

CREATE OR REPLACE TRIGGER public_opinion_before_insert
  BEFORE INSERT ON public.opinion
  FOR EACH ROW EXECUTE FUNCTION public.opinion_before_insert();

CREATE OR REPLACE TRIGGER public_vote_beacon_before_insert
  BEFORE INSERT ON public.vote_beacon
  FOR EACH ROW EXECUTE FUNCTION public.vote_beacon_before_insert();

CREATE OR REPLACE TRIGGER public_vote_comment_before_insert
  BEFORE INSERT ON public.vote_comment
  FOR EACH ROW EXECUTE FUNCTION public.vote_comment_before_insert();

CREATE OR REPLACE TRIGGER public_vote_user_before_insert
  BEFORE INSERT ON public.vote_user
  FOR EACH ROW EXECUTE FUNCTION public.vote_user_before_insert();

CREATE OR REPLACE TRIGGER set_public_beacon_updated_at
  BEFORE UPDATE ON public.beacon
  FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updated_at();

CREATE OR REPLACE TRIGGER set_public_invitation_updated_at
  BEFORE UPDATE ON public.invitation
  FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updated_at();

CREATE OR REPLACE TRIGGER set_public_message_updated_at
  BEFORE UPDATE ON public.message
  FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updated_at();

CREATE OR REPLACE TRIGGER set_public_user_vsids_updated_at
  BEFORE UPDATE ON public.user_vsids
  FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updated_at();

CREATE OR REPLACE TRIGGER set_public_vote_beacon_updated_at
  BEFORE UPDATE ON public.vote_beacon
  FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updated_at();

CREATE OR REPLACE TRIGGER set_public_vote_comment_updated_at
  BEFORE UPDATE ON public.vote_comment
  FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updated_at();

CREATE OR REPLACE TRIGGER set_public_vote_user_updated_at
  BEFORE UPDATE ON public.vote_user
  FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updated_at();

-- meritrank_init(): backfill MeritRank from existing data (call via SELECT meritrank_init();)
-- Uses mr_bulk_load_edges for a single RPC instead of many mr_put_edge calls.
CREATE OR REPLACE FUNCTION public.meritrank_init()
  RETURNS integer
  LANGUAGE plpgsql
  STABLE
  AS $$
DECLARE
  _src text[];
  _dst text[];
  _weight float8[];
  _magnitude bigint[];
  _context text[];
  _total integer := 0;
  _edge_count integer;
BEGIN
  WITH all_edges AS (
    -- Edges User -> User (vote)
    SELECT subject AS src, object AS dst, amount::float8 AS weight, ticker::bigint AS magnitude, ''::text AS context
    FROM vote_user
    UNION ALL
    -- Edges Beacon -> Author
    SELECT id, user_id, 1.0::float8, 0::bigint, context FROM "beacon"
    UNION ALL
    -- Edges Author -> Beacon
    SELECT user_id, id, 1.0::float8, ticker::bigint, context FROM "beacon"
    UNION ALL
    -- Edges User -> Beacon (vote)
    SELECT vb.subject, vb.object, vb.amount::float8, vb.ticker::bigint, b.context
    FROM vote_beacon vb JOIN "beacon" b ON b.id = vb.object
    UNION ALL
    -- Edges Comment -> Author
    SELECT c.id, c.user_id, 1.0::float8, 0::bigint, c.context
    FROM "comment" c JOIN "beacon" b ON c.beacon_id = b.id
    UNION ALL
    -- Edges Author -> Comment
    SELECT c.user_id, c.id, 1.0::float8, c.ticker::bigint, c.context
    FROM "comment" c JOIN "beacon" b ON c.beacon_id = b.id
    UNION ALL
    -- Edges User -> Comment (vote)
    SELECT vc.subject, vc.object, vc.amount::float8, vc.ticker::bigint, b.context
    FROM vote_comment vc
    JOIN "comment" c ON c.id = vc.object
    JOIN "beacon" b ON b.id = c.beacon_id
    UNION ALL
    -- Edges Author -> Opinion
    SELECT subject, id, (abs(amount))::float8, ticker::bigint, ''::text FROM "opinion"
    UNION ALL
    -- Edges Opinion -> Author
    SELECT id, subject, 1.0::float8, ticker::bigint, ''::text FROM "opinion"
    UNION ALL
    -- Edges Opinion -> User
    SELECT id, object, (sign(amount))::float8, ticker::bigint, ''::text FROM "opinion"
    UNION ALL
    -- Pollings and Variants (variant -> polling)
    SELECT pv.id, p.id, 1.0::float8, 0::bigint, ''::text
    FROM polling p
    JOIN polling_variant pv ON p.id = pv.polling_id
    WHERE p.enabled = true
    UNION ALL
    -- Pollings Acts
    SELECT pa.author_id, pa.polling_variant_id, 1.0::float8, 0::bigint, ''::text
    FROM polling_act pa
    JOIN polling p ON p.id = pa.polling_id
    WHERE p.enabled = true
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

  PERFORM mr_bulk_load_edges(_src, _dst, _weight, _magnitude, _context, 120000);

  -- Read Updates Filters
  SELECT _total + count(*)::int INTO _total
  FROM (SELECT mr_set_new_edges_filter(user_id, filter) FROM user_updates) AS _;

  RETURN _total;
END;
$$;
