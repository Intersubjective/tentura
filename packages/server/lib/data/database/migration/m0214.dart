part of '_migrations.dart';

/// First-response claim of a Post (plan §4.4): one row per (Post, member),
/// written by `post_claim_first_response` on the member's first message or
/// reaction. The winning call engages the member's inbound contact edge.
final m0214 = Migration('0214', [
  r'''
CREATE TABLE public.post_first_response (
    beacon_id text NOT NULL REFERENCES public.beacon(id) ON DELETE CASCADE,
    user_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
    source_kind smallint NOT NULL,
    source_id text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    PRIMARY KEY (beacon_id, user_id),
    CONSTRAINT post_first_response_source_kind_chk CHECK (source_kind IN (1, 2))
)
''',
  r'''
CREATE FUNCTION public.post_claim_first_response(p_beacon text, p_user text, p_kind smallint, p_source text) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
  _n integer;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.beacon b
    WHERE b.id = p_beacon AND b.kind = 1 AND b.user_id <> p_user
  ) THEN
    RETURN false;
  END IF;
  INSERT INTO public.post_first_response (beacon_id, user_id, source_kind, source_id)
  VALUES (p_beacon, p_user, p_kind, p_source)
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS _n = ROW_COUNT;
  IF _n = 1 THEN
    PERFORM public.contact_engage(p_beacon, p_user);
    RETURN true;
  END IF;
  RETURN false;
END;
$$
''',
]);
