part of '_migrations.dart';

/// Fact history (issue #181 plan §8.1, written there as `m0196`): the
/// `beacon_fact_card_revision` log, provenance columns on the card, the fact
/// scope on activity events, quote columns on room messages, the H1–H3 FK
/// action indexes, and a backfill of one revision per existing fact.
///
/// The revision table has no NOTIFY trigger on purpose.
///
/// The guard runs first: step 6 widens the unique source index from active
/// facts to active and corrected ones, which only succeeds if no source message
/// already has both. The whole migration runs in one transaction, so the guard
/// aborting leaves the database at `0198`.
final m0199 = Migration('0199', [
  // Guard for step 6 (expected: zero rows).
  r'''
DO $$
DECLARE
  dup_source text;
BEGIN
  SELECT f.source_message_id INTO dup_source
  FROM public.beacon_fact_card f
  WHERE f.source_message_id IS NOT NULL
    AND f.status IN (0, 1)
  GROUP BY f.source_message_id
  HAVING count(*) FILTER (WHERE f.status = 0) > 0
     AND count(*) FILTER (WHERE f.status = 1) > 0
  LIMIT 1;

  IF dup_source IS NOT NULL THEN
    RAISE EXCEPTION
      'm0199: source message % has both an active and a corrected fact; '
      'resolve the duplicate before migrating', dup_source;
  END IF;
END
$$;
''',

  // 1. Revision log (text versions only).
  r'''
CREATE TABLE public.beacon_fact_card_revision (
  id           text PRIMARY KEY
               DEFAULT concat('FR', substring(replace(gen_random_uuid()::text, '-', ''), 1, 12)),
  fact_card_id text NOT NULL REFERENCES public.beacon_fact_card(id)
               ON UPDATE CASCADE ON DELETE CASCADE,
  seq          integer  NOT NULL,
  fact_text    text     NOT NULL CHECK (btrim(fact_text) <> ''),
  actor_id     text REFERENCES public."user"(id) ON UPDATE CASCADE ON DELETE SET NULL,
  kind         smallint NOT NULL CHECK (kind IN (0, 1, 2, 3)),
  restored_from_seq integer,
  created_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT beacon_fact_card_revision_seq_uq UNIQUE (fact_card_id, seq)
);
''',

  // Serves the user-erasure FK action and the per-actor edit rate limit.
  '''
CREATE INDEX beacon_fact_card_revision_actor_idx
  ON public.beacon_fact_card_revision (actor_id, created_at DESC)
  WHERE actor_id IS NOT NULL;
''',

  // 2. Head pointer + denormalised provenance on the card.
  '''
ALTER TABLE public.beacon_fact_card
  ADD COLUMN revision_seq       integer  NOT NULL DEFAULT 1,
  ADD COLUMN last_edited_by     text REFERENCES public."user"(id) ON UPDATE CASCADE ON DELETE SET NULL,
  ADD COLUMN last_edited_at     timestamptz,
  ADD COLUMN other_editor_count smallint NOT NULL DEFAULT 0,
  ADD COLUMN history_truncated  boolean  NOT NULL DEFAULT false;
''',

  // 3. Fact-scoped activity events become index-addressable.
  '''
ALTER TABLE public.beacon_activity_event
  ADD COLUMN fact_card_id text REFERENCES public.beacon_fact_card(id)
    ON UPDATE CASCADE ON DELETE SET NULL;
''',

  '''
CREATE INDEX beacon_activity_event_fact_card_idx
  ON public.beacon_activity_event (fact_card_id, created_at DESC)
  WHERE fact_card_id IS NOT NULL;
''',

  // 4. Quote columns: one composite FK onto the revision's (fact_card_id,
  //    seq). A composite ON DELETE SET NULL nulls both columns, so the pair
  //    CHECK holds when a beacon (and so its facts and revisions) is deleted.
  '''
ALTER TABLE public.beacon_room_message
  ADD COLUMN quoted_fact_card_id      text,
  ADD COLUMN quoted_fact_revision_seq integer,
  ADD CONSTRAINT beacon_room_message_quote_pair_ck
    CHECK ((quoted_fact_card_id IS NULL) = (quoted_fact_revision_seq IS NULL)),
  ADD CONSTRAINT beacon_room_message_quoted_revision_fkey
    FOREIGN KEY (quoted_fact_card_id, quoted_fact_revision_seq)
    REFERENCES public.beacon_fact_card_revision (fact_card_id, seq)
    ON UPDATE CASCADE ON DELETE SET NULL;
''',

  '''
CREATE INDEX beacon_room_message_quoted_fact_idx
  ON public.beacon_room_message (quoted_fact_card_id, quoted_fact_revision_seq)
  WHERE quoted_fact_card_id IS NOT NULL;
''',

  // 5. FK-action indexes missing until now (plan §8.9 H1–H3).
  '''
CREATE INDEX beacon_room_message_linked_fact_idx
  ON public.beacon_room_message (linked_fact_card_id)
  WHERE linked_fact_card_id IS NOT NULL;
''',

  '''
CREATE INDEX beacon_fact_card_source_message_idx
  ON public.beacon_fact_card (source_message_id)
  WHERE source_message_id IS NOT NULL;
''',

  '''
CREATE INDEX beacon_room_message_attachment_message_idx
  ON public.beacon_room_message_attachment (message_id, "position");
''',

  // 6. The duplicate-source guard covers corrected facts too.
  'DROP INDEX public.beacon_fact_card_unique_active_source_idx;',

  '''
CREATE UNIQUE INDEX beacon_fact_card_unique_live_source_idx
  ON public.beacon_fact_card (source_message_id)
  WHERE status IN (0, 1) AND source_message_id IS NOT NULL;
''',

  // 7. Inbox snippet (plan §8.6).
  '''
CREATE INDEX beacon_fact_card_public_live_idx
  ON public.beacon_fact_card (beacon_id, created_at DESC)
  WHERE visibility = 0 AND status IN (0, 1);
''',

  // Backfill. Active facts (status 0) were never edited: revision 1 is the
  // pinner's text at pin time.
  '''
INSERT INTO public.beacon_fact_card_revision (fact_card_id, seq, fact_text, actor_id, kind, created_at)
SELECT id, 1, fact_text, pinned_by, 0, created_at
FROM public.beacon_fact_card WHERE status = 0;
''',

  // Corrected (1) and removed (2) facts: who changed the text and when is
  // unrecoverable, so revision 1 is an "imported" baseline with no author,
  // dated at migration time.
  '''
INSERT INTO public.beacon_fact_card_revision (fact_card_id, seq, fact_text, actor_id, kind, created_at)
SELECT id, 1, fact_text, NULL, 3, now()
FROM public.beacon_fact_card WHERE status IN (1, 2);
''',

  // Only status 1 is known to have been edited; removed facts get no flag.
  '''
UPDATE public.beacon_fact_card
SET history_truncated = true
WHERE status = 1;
''',

  // factPinned (2) and factVisibilityChanged (14) carry the fact id in `diff`.
  '''
UPDATE public.beacon_activity_event e
SET fact_card_id = e.diff->>'factCardId'
WHERE e.type IN (2, 14)
  AND e.diff ? 'factCardId'
  AND EXISTS (SELECT 1 FROM public.beacon_fact_card f WHERE f.id = e.diff->>'factCardId');
''',
]);
