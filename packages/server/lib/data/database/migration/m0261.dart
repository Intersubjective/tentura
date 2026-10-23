part of '_migrations.dart';

/// People tags (#699): an owner's private tags over other people, their
/// members, auto-tag preferences, first-seen markers, suggestion state and
/// the idempotency log. The V2 API is the only reader and writer, so none of
/// these tables is tracked by Hasura. Size and ownership rules live here: a
/// member row can never sit under another owner's tag (composite FK), and
/// every row goes with its owner (or tagged person) on user deletion.
final m0261 = Migration('0261', [
  '''
CREATE TABLE public.person_tag (
  id text PRIMARY KEY,
  owner_id text NOT NULL REFERENCES public."user" (id) ON DELETE CASCADE,
  name text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 32),
  glyph text NOT NULL CHECK (char_length(glyph) BETWEEN 1 AND 8),
  color smallint NOT NULL CHECK (color BETWEEN 0 AND 7),
  ord integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (id, owner_id)
)
''',
  '''
CREATE UNIQUE INDEX person_tag_owner_name_uq
  ON public.person_tag (owner_id, lower(name))
''',
  '''
CREATE INDEX person_tag_owner_ord_idx ON public.person_tag (owner_id, ord)
''',
  '''
CREATE TABLE public.person_tag_member (
  tag_id text NOT NULL,
  owner_id text NOT NULL REFERENCES public."user" (id) ON DELETE CASCADE,
  person_id text NOT NULL REFERENCES public."user" (id) ON DELETE CASCADE,
  source smallint NOT NULL CHECK (source BETWEEN 0 AND 4),
  added_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tag_id, person_id),
  FOREIGN KEY (tag_id, owner_id)
    REFERENCES public.person_tag (id, owner_id) ON DELETE CASCADE,
  CHECK (owner_id <> person_id)
)
''',
  '''
CREATE INDEX person_tag_member_owner_person_idx
  ON public.person_tag_member (owner_id, person_id)
''',
  '''
CREATE TABLE public.person_auto_tag_pref (
  owner_id text NOT NULL REFERENCES public."user" (id) ON DELETE CASCADE,
  kind smallint NOT NULL,
  show_in_filters boolean NOT NULL,
  PRIMARY KEY (owner_id, kind)
)
''',
  '''
CREATE TABLE public.person_field_first_seen (
  viewer_id text NOT NULL REFERENCES public."user" (id) ON DELETE CASCADE,
  peer_id text NOT NULL REFERENCES public."user" (id) ON DELETE CASCADE,
  first_seen_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (viewer_id, peer_id)
)
''',
  '''
CREATE TABLE public.person_tag_suggestion_state (
  owner_id text PRIMARY KEY REFERENCES public."user" (id) ON DELETE CASCADE,
  consecutive_skips smallint NOT NULL DEFAULT 0,
  silenced_until timestamptz,
  disabled boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now()
)
''',
  '''
CREATE TABLE public.person_tag_op_log (
  owner_id text NOT NULL REFERENCES public."user" (id) ON DELETE CASCADE,
  client_op_id text NOT NULL,
  fingerprint text NOT NULL,
  result jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (owner_id, client_op_id)
)
''',
  '''
CREATE TABLE public.person_tag_revision (
  owner_id text PRIMARY KEY REFERENCES public."user" (id) ON DELETE CASCADE,
  revision bigint NOT NULL DEFAULT 0
)
''',
]);
