part of '_migrations.dart';

// V1 feedless redesign: forwarding, commitments, author updates, inbox projection.
final m0014 = Migration('0014', [
  // beacon.state smallint lifecycle: 0=OPEN, 1=CLOSED, 2=DELETED, 3=DRAFT, 4=PENDING_REVIEW
  '''
ALTER TABLE public.beacon
  ADD COLUMN IF NOT EXISTS state smallint NOT NULL DEFAULT 0;
''',

  // beacon_forward_edge: one row per sender->recipient forward action
  r'''
CREATE TABLE IF NOT EXISTS public.beacon_forward_edge (
  id text DEFAULT concat('F', "substring"((gen_random_uuid())::text, '\w{12}')) NOT NULL,
  beacon_id text NOT NULL,
  context text,
  sender_id text NOT NULL,
  recipient_id text NOT NULL,
  note text DEFAULT ''::text NOT NULL,
  parent_edge_id text,
  batch_id text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  PRIMARY KEY (id),
  CONSTRAINT bfe_beacon_id_fkey FOREIGN KEY (beacon_id)
    REFERENCES public.beacon(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT bfe_sender_id_fkey FOREIGN KEY (sender_id)
    REFERENCES public."user"(id) ON UPDATE RESTRICT ON DELETE CASCADE,
  CONSTRAINT bfe_recipient_id_fkey FOREIGN KEY (recipient_id)
    REFERENCES public."user"(id) ON UPDATE RESTRICT ON DELETE CASCADE,
  CONSTRAINT bfe_parent_edge_id_fkey FOREIGN KEY (parent_edge_id)
    REFERENCES public.beacon_forward_edge(id) ON UPDATE RESTRICT ON DELETE SET NULL,
  CONSTRAINT bfe_note_length CHECK (char_length(note) <= 2048)
);
''',

  // beacon_commitment: explicit responsibility signal
  r'''
CREATE TABLE IF NOT EXISTS public.beacon_commitment (
  beacon_id text NOT NULL,
  user_id text NOT NULL,
  message text DEFAULT ''::text NOT NULL,
  status smallint DEFAULT 0 NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT bc_pkey PRIMARY KEY (beacon_id, user_id),
  CONSTRAINT bc_beacon_id_fkey FOREIGN KEY (beacon_id)
    REFERENCES public.beacon(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT bc_user_id_fkey FOREIGN KEY (user_id)
    REFERENCES public."user"(id) ON UPDATE RESTRICT ON DELETE CASCADE,
  CONSTRAINT bc_message_length CHECK (char_length(message) <= 2048)
);
''',

  // beacon_update: author-posted timeline updates
  r'''
CREATE TABLE IF NOT EXISTS public.beacon_update (
  id text DEFAULT concat('A', "substring"((gen_random_uuid())::text, '\w{12}')) NOT NULL,
  beacon_id text NOT NULL,
  author_id text NOT NULL,
  content text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  PRIMARY KEY (id),
  CONSTRAINT bu_beacon_id_fkey FOREIGN KEY (beacon_id)
    REFERENCES public.beacon(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT bu_author_id_fkey FOREIGN KEY (author_id)
    REFERENCES public."user"(id) ON UPDATE RESTRICT ON DELETE CASCADE,
  CONSTRAINT bu_content_length CHECK ((char_length(content) > 0) AND (char_length(content) <= 2048))
);
''',

  // inbox_item: deduplicated inbox projection keyed by (user_id, beacon_id)
  '''
CREATE TABLE IF NOT EXISTS public.inbox_item (
  user_id text NOT NULL,
  beacon_id text NOT NULL,
  context text,
  forward_count integer DEFAULT 0 NOT NULL,
  latest_forward_at timestamp with time zone DEFAULT now() NOT NULL,
  latest_note_preview text DEFAULT ''::text NOT NULL,
  is_hidden boolean DEFAULT false NOT NULL,
  is_watching boolean DEFAULT false NOT NULL,
  CONSTRAINT ii_pkey PRIMARY KEY (user_id, beacon_id),
  CONSTRAINT ii_user_id_fkey FOREIGN KEY (user_id)
    REFERENCES public."user"(id) ON UPDATE RESTRICT ON DELETE CASCADE,
  CONSTRAINT ii_beacon_id_fkey FOREIGN KEY (beacon_id)
    REFERENCES public.beacon(id) ON UPDATE CASCADE ON DELETE CASCADE
);
''',

  // Indexes for forward edges
  '''
CREATE INDEX IF NOT EXISTS bfe_recipient_context_created
  ON public.beacon_forward_edge USING btree (recipient_id, context, created_at DESC);
''',
  '''
CREATE INDEX IF NOT EXISTS bfe_beacon_id
  ON public.beacon_forward_edge USING btree (beacon_id);
''',
  '''
CREATE INDEX IF NOT EXISTS bfe_sender_id
  ON public.beacon_forward_edge USING btree (sender_id);
''',

  // Indexes for inbox
  '''
CREATE INDEX IF NOT EXISTS ii_user_context_latest
  ON public.inbox_item USING btree (user_id, context, latest_forward_at DESC);
''',

  // Indexes for commitments
  '''
CREATE INDEX IF NOT EXISTS bc_user_status
  ON public.beacon_commitment USING btree (user_id, status, updated_at DESC);
''',

  // Indexes for beacon updates
  '''
CREATE INDEX IF NOT EXISTS bu_beacon_created
  ON public.beacon_update USING btree (beacon_id, created_at DESC);
''',

  // Trigger: auto-maintain inbox_item on beacon_forward_edge insert
  r'''
CREATE OR REPLACE FUNCTION public.inbox_item_on_forward_insert()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  INSERT INTO public.inbox_item (user_id, beacon_id, context, forward_count, latest_forward_at, latest_note_preview)
  VALUES (NEW.recipient_id, NEW.beacon_id, NEW.context, 1, NEW.created_at,
    CASE WHEN char_length(NEW.note) > 200 THEN substring(NEW.note FROM 1 FOR 200) ELSE NEW.note END)
  ON CONFLICT (user_id, beacon_id) DO UPDATE SET
    forward_count = inbox_item.forward_count + 1,
    latest_forward_at = GREATEST(inbox_item.latest_forward_at, NEW.created_at),
    latest_note_preview = CASE
      WHEN NEW.created_at > inbox_item.latest_forward_at
        THEN CASE WHEN char_length(NEW.note) > 200 THEN substring(NEW.note FROM 1 FOR 200) ELSE NEW.note END
      ELSE inbox_item.latest_note_preview
    END,
    context = COALESCE(NEW.context, inbox_item.context);
  RETURN NEW;
END;
$$;
''',

  '''
CREATE OR REPLACE TRIGGER inbox_item_on_forward_insert
  AFTER INSERT ON public.beacon_forward_edge
  FOR EACH ROW EXECUTE FUNCTION public.inbox_item_on_forward_insert();
''',

  // Trigger: updated_at on beacon_commitment
  '''
CREATE OR REPLACE TRIGGER set_beacon_commitment_updated_at
  BEFORE UPDATE ON public.beacon_commitment
  FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updated_at();
''',
]);
